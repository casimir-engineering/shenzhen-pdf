/* Win32 window + message pump. See spdf_win_window.h for the layering rule.
 *
 * Every Win32 call here is an explicit *W call. guest-build.cmd does not
 * define UNICODE, so the undecorated names would silently resolve to the ANSI
 * variants and mangle every non-ASCII document title -- the exact class of bug
 * windows-port-plan.md sec 2.2 warns about ("Call *W APIs exclusively; never
 * *A").
 */
#include "spdf_win_window.h"

#include <windowsx.h> /* GET_X_LPARAM / GET_Y_LPARAM */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#pragma comment(lib, "user32.lib")

static const wchar_t kWindowClass[] = L"ShenzhenPDFWindow";

struct spdf_win_window {
    HWND hwnd;
    spdf_win_d2d* d2d;
    ID2D1HwndRenderTarget* target;
    spdf_win_scene_fn scene_fn;
    spdf_win_input_fn input_fn;
    void* user;
    UINT dpi;
    int exit_code;

    /* Drag-to-pan state. `dragging` is the authority, not GetCapture(): a
     * capture can be taken away (an Alt+Tab, a system modal) and the resulting
     * WM_CAPTURECHANGED must end the drag, or the next mouse move a second
     * later would pan by the distance the cursor travelled in between. */
    bool dragging;
    POINT drag_last;
};

/* SetProcessDpiAwarenessContext and GetDpiForWindow both arrived in Windows 10
 * 1607/1703. Resolving them dynamically means one binary runs everywhere and
 * simply looks slightly wrong on a machine older than the feature, instead of
 * failing to start. */
typedef BOOL(WINAPI* set_dpi_ctx_fn)(DPI_AWARENESS_CONTEXT);
typedef UINT(WINAPI* get_dpi_for_window_fn)(HWND);

void spdf_win_enable_dpi_awareness(void) {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (!user32) return;
    set_dpi_ctx_fn set_ctx = (set_dpi_ctx_fn)GetProcAddress(user32, "SetProcessDpiAwarenessContext");
    if (set_ctx) set_ctx(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
}

static UINT window_dpi(HWND hwnd) {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (user32) {
        get_dpi_for_window_fn get_dpi = (get_dpi_for_window_fn)GetProcAddress(user32, "GetDpiForWindow");
        if (get_dpi) {
            UINT dpi = get_dpi(hwnd);
            if (dpi >= 48 && dpi <= 960) return dpi;
        }
    }
    return USER_DEFAULT_SCREEN_DPI;
}

float spdf_win_window_dpi_scale(const spdf_win_window* window) {
    if (!window || window->dpi == 0) return 1.0f;
    return (float)window->dpi / (float)USER_DEFAULT_SCREEN_DPI;
}

static void discard_target(spdf_win_window* window) {
    if (!window->target) return;
    spdf_win_d2d_release_target(window->d2d, window->target);
    window->target->Release();
    window->target = NULL;
}

/* Creates the HWND render target on first paint, and resizes it in place
 * afterwards. Lazily, because a target created before the window has its
 * final size is a target that gets resized immediately anyway, and Phase 1's
 * whole point is that nothing eager happens on the launch path. */
static HRESULT ensure_target(spdf_win_window* window, UINT px_w, UINT px_h) {
    if (window->target) {
        return window->target->Resize(D2D1::SizeU(px_w, px_h));
    }
    D2D1_RENDER_TARGET_PROPERTIES props = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE),
        96.0f, 96.0f);
    D2D1_HWND_RENDER_TARGET_PROPERTIES hwnd_props =
        D2D1::HwndRenderTargetProperties(window->hwnd, D2D1::SizeU(px_w, px_h), D2D1_PRESENT_OPTIONS_NONE);
    return spdf_win_d2d_factory(window->d2d)->CreateHwndRenderTarget(props, hwnd_props, &window->target);
}

static void paint(spdf_win_window* window) {
    RECT rc;
    if (!GetClientRect(window->hwnd, &rc)) return;

    UINT px_w = (UINT)(rc.right - rc.left);
    UINT px_h = (UINT)(rc.bottom - rc.top);
    if (px_w == 0 || px_h == 0) return;

    if (FAILED(ensure_target(window, px_w, px_h))) {
        discard_target(window);
        return;
    }

    spdf_win_scene scene;
    memset(&scene, 0, sizeof(scene));
    scene.fit = SPDF_WIN_FIT_CANVAS;
    scene.target_px_w = px_w;
    scene.target_px_h = px_h;
    scene.dpi_scale = spdf_win_window_dpi_scale(window);
    /* A handler that declines leaves an EMPTY scene, not a half-filled one: it
     * may have written a page list and then decided against it, and drawing
     * from a list its owner has disclaimed is how a stale pointer gets
     * dereferenced. */
    if (window->scene_fn && !window->scene_fn(window->user, &scene)) {
        scene.page = NULL;
        scene.pages = NULL;
        scene.page_count = 0;
    }

    HRESULT hr = spdf_win_paint(window->d2d, window->target, &scene);
    if (hr == D2DERR_RECREATE_TARGET) {
        /* The display changed, the GPU was reset, or the session was locked.
         * Throw the target away and ask for another paint; the next one
         * rebuilds it. */
        discard_target(window);
        InvalidateRect(window->hwnd, NULL, FALSE);
    }
}

/* Fills in the fields every event carries and dispatches. Returns non-zero
 * when the handler changed the view, and invalidates when it did. */
static int dispatch(spdf_win_window* window, spdf_win_input* input) {
    RECT rc = {0, 0, 0, 0};

    if (!window->input_fn) return 0;
    GetClientRect(window->hwnd, &rc);
    input->view_px_w = (unsigned)(rc.right - rc.left);
    input->view_px_h = (unsigned)(rc.bottom - rc.top);
    input->mods = (GetKeyState(VK_CONTROL) < 0 ? SPDF_WIN_MOD_CTRL : 0u) |
                  (GetKeyState(VK_SHIFT) < 0 ? SPDF_WIN_MOD_SHIFT : 0u);
    if (!window->input_fn(window->user, input)) return 0;
    InvalidateRect(window->hwnd, NULL, FALSE);
    return 1;
}

/* One wheel notch in device pixels. SPI_GETWHEELSCROLLLINES is the user's own
 * setting and honouring it is the difference between a viewer that feels like
 * the rest of the desktop and one that does not; WHEEL_PAGESCROLL (0xFFFFFFFF)
 * is its "scroll a screenful" value, which the caller can only express if we
 * hand it a distance rather than a notch count. */
static float wheel_step(const spdf_win_window* window, unsigned view_px_h) {
    UINT lines = 3;
    float scale = spdf_win_window_dpi_scale(window);

    SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
    if (lines == WHEEL_PAGESCROLL) return (float)view_px_h * 0.9f;
    if (lines == 0) lines = 3;
    return (float)lines * 20.0f * scale;
}

/* Mouse wheel, both axes. Ctrl zooms at the cursor; Shift turns a vertical
 * wheel horizontal, which is the Windows convention for a one-axis mouse. */
static void on_wheel(spdf_win_window* window, WPARAM wparam, LPARAM lparam, bool horizontal) {
    spdf_win_input input;
    POINT pt;
    float notches = (float)GET_WHEEL_DELTA_WPARAM(wparam) / (float)WHEEL_DELTA;
    RECT rc = {0, 0, 0, 0};

    memset(&input, 0, sizeof(input));
    /* WM_MOUSEWHEEL carries SCREEN coordinates, unlike every other mouse
     * message in this file. Converting is not optional: the un-converted point
     * would anchor a Ctrl+wheel zoom to wherever the window happens to sit on
     * the desktop. */
    pt.x = GET_X_LPARAM(lparam);
    pt.y = GET_Y_LPARAM(lparam);
    ScreenToClient(window->hwnd, &pt);
    input.x = (float)pt.x;
    input.y = (float)pt.y;

    if (!horizontal && (GET_KEYSTATE_WPARAM(wparam) & MK_CONTROL)) {
        input.kind = SPDF_WIN_INPUT_ZOOM;
        /* Geometric, so N notches out exactly undo N notches in. */
        input.factor = powf(1.1f, notches);
        dispatch(window, &input);
        return;
    }

    GetClientRect(window->hwnd, &rc);
    float step = notches * wheel_step(window, (unsigned)(rc.bottom - rc.top));
    input.kind = SPDF_WIN_INPUT_SCROLL;
    if (horizontal || (GET_KEYSTATE_WPARAM(wparam) & MK_SHIFT)) input.dx = horizontal ? step : -step;
    else input.dy = -step;
    dispatch(window, &input);
}

static void end_drag(spdf_win_window* window) {
    if (!window->dragging) return;
    window->dragging = false;
    if (GetCapture() == window->hwnd) ReleaseCapture();
}

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
    spdf_win_window* window = (spdf_win_window*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);

    if (msg == WM_NCCREATE) {
        CREATESTRUCTW* cs = (CREATESTRUCTW*)lparam;
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)cs->lpCreateParams);
        return DefWindowProcW(hwnd, msg, wparam, lparam);
    }
    if (!window) return DefWindowProcW(hwnd, msg, wparam, lparam);

    switch (msg) {
        case WM_PAINT: {
            PAINTSTRUCT ps;
            BeginPaint(hwnd, &ps);
            paint(window);
            EndPaint(hwnd, &ps);
            return 0;
        }
        /* D2D repaints the whole client area every time, so letting GDI erase
         * it first buys nothing but a flash of white on every resize. */
        case WM_ERASEBKGND:
            return 1;
        case WM_SIZE:
            if (wparam != SIZE_MINIMIZED && window->target)
                window->target->Resize(D2D1::SizeU(LOWORD(lparam), HIWORD(lparam)));
            return 0;
        case WM_MOUSEWHEEL:
            on_wheel(window, wparam, lparam, false);
            return 0;
        case WM_MOUSEHWHEEL:
            on_wheel(window, wparam, lparam, true);
            return 0;
        case WM_LBUTTONDOWN:
        case WM_MBUTTONDOWN:
            window->dragging = true;
            window->drag_last.x = GET_X_LPARAM(lparam);
            window->drag_last.y = GET_Y_LPARAM(lparam);
            SetCapture(hwnd);
            SetFocus(hwnd);
            return 0;
        case WM_MOUSEMOVE: {
            if (!window->dragging) break;
            spdf_win_input input;
            POINT now = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
            memset(&input, 0, sizeof(input));
            input.kind = SPDF_WIN_INPUT_SCROLL;
            /* Dragging the paper down scrolls the document up, so the scroll
             * delta is the negated cursor delta -- grab-and-pull, not
             * push-the-scrollbar. */
            input.dx = (float)(window->drag_last.x - now.x);
            input.dy = (float)(window->drag_last.y - now.y);
            input.x = (float)now.x;
            input.y = (float)now.y;
            window->drag_last = now;
            dispatch(window, &input);
            return 0;
        }
        case WM_LBUTTONUP:
        case WM_MBUTTONUP:
            end_drag(window);
            return 0;
        case WM_CAPTURECHANGED:
            window->dragging = false;
            return 0;
        case WM_SETCURSOR:
            if (LOWORD(lparam) == HTCLIENT) {
                SetCursor(LoadCursorW(NULL, MAKEINTRESOURCEW(window->dragging ? 32646 /* IDC_SIZEALL */
                                                                              : 32512 /* IDC_ARROW */)));
                return TRUE;
            }
            break;
        case WM_DPICHANGED: {
            /* Windows hands us the rectangle the window should occupy on the
             * monitor it just moved to. Honouring it is what makes a drag
             * between a 1x and a 2x display keep the window physically the
             * same size instead of doubling. */
            window->dpi = HIWORD(wparam);
            RECT* suggested = (RECT*)lparam;
            SetWindowPos(hwnd, NULL, suggested->left, suggested->top, suggested->right - suggested->left,
                         suggested->bottom - suggested->top, SWP_NOZORDER | SWP_NOACTIVATE);
            InvalidateRect(hwnd, NULL, FALSE);
            return 0;
        }
        case WM_KEYDOWN: {
            if (wparam == VK_ESCAPE) {
                PostMessageW(hwnd, WM_CLOSE, 0, 0);
                return 0;
            }
            spdf_win_input input;
            memset(&input, 0, sizeof(input));
            input.kind = SPDF_WIN_INPUT_KEY;
            input.key = (unsigned)wparam;
            if (dispatch(window, &input)) return 0;
            break;
        }
        case WM_DESTROY:
            end_drag(window);
            discard_target(window);
            window->hwnd = NULL;
            PostQuitMessage(window->exit_code);
            return 0;
        default:
            break;
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static int register_class(HINSTANCE instance) {
    WNDCLASSEXW wc;
    memset(&wc, 0, sizeof(wc));
    wc.cbSize = sizeof(wc);
    /* Redraw the whole client area on any size change: the page is centred, so
     * a horizontal resize moves pixels that a partial invalidation would
     * leave stale. */
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = window_proc;
    wc.hInstance = instance;
    /* MAKEINTRESOURCEW, not IDC_ARROW: guest-build.cmd does not define
     * UNICODE, so IDC_ARROW expands to the ANSI MAKEINTRESOURCEA and will not
     * convert to LoadCursorW's LPCWSTR. Same trap as the *A/*W entry points,
     * one level down in the macros. */
    wc.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512 /* IDC_ARROW */));
    wc.hbrBackground = NULL; /* see WM_ERASEBKGND */
    wc.lpszClassName = kWindowClass;

    if (RegisterClassExW(&wc)) return 1;
    return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

spdf_win_window* spdf_win_window_create(spdf_win_d2d* d2d, const wchar_t* title, int client_px_w, int client_px_h,
                                        spdf_win_scene_fn scene_fn, spdf_win_input_fn input_fn, void* user, char* err,
                                        size_t err_len) {
    if (err && err_len) err[0] = '\0';
    if (!d2d) return NULL;

    HINSTANCE instance = GetModuleHandleW(NULL);
    if (!register_class(instance)) {
        if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "RegisterClassExW failed (%lu)", GetLastError());
        return NULL;
    }

    spdf_win_window* window = (spdf_win_window*)calloc(1, sizeof(*window));
    if (!window) {
        if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "out of memory");
        return NULL;
    }
    window->d2d = d2d;
    window->scene_fn = scene_fn;
    window->input_fn = input_fn;
    window->user = user;
    window->dpi = USER_DEFAULT_SCREEN_DPI;

    if (client_px_w < 200) client_px_w = 200;
    if (client_px_h < 200) client_px_h = 200;
    RECT rc = {0, 0, client_px_w, client_px_h};
    AdjustWindowRectEx(&rc, WS_OVERLAPPEDWINDOW, FALSE, 0);

    window->hwnd = CreateWindowExW(0, kWindowClass, title ? title : L"ShenzhenPDF", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT,
                                   CW_USEDEFAULT, rc.right - rc.left, rc.bottom - rc.top, NULL, NULL, instance,
                                   window);
    if (!window->hwnd) {
        if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "CreateWindowExW failed (%lu)", GetLastError());
        free(window);
        return NULL;
    }

    /* Now that there is an HWND we can ask which monitor it landed on. The
     * frame was sized in 96-dpi units, so on a 2x display resize it once
     * rather than leaving a half-size window. */
    window->dpi = window_dpi(window->hwnd);
    if (window->dpi != USER_DEFAULT_SCREEN_DPI) {
        float s = spdf_win_window_dpi_scale(window);
        RECT scaled = {0, 0, (LONG)(client_px_w * s), (LONG)(client_px_h * s)};
        AdjustWindowRectEx(&scaled, WS_OVERLAPPEDWINDOW, FALSE, 0);
        SetWindowPos(window->hwnd, NULL, 0, 0, scaled.right - scaled.left, scaled.bottom - scaled.top,
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
    return window;
}

void spdf_win_window_show(spdf_win_window* window) {
    if (!window || !window->hwnd) return;
    ShowWindow(window->hwnd, SW_SHOWNORMAL);
    UpdateWindow(window->hwnd);
}

void spdf_win_window_invalidate(spdf_win_window* window) {
    if (window && window->hwnd) InvalidateRect(window->hwnd, NULL, FALSE);
}

int spdf_win_window_run(spdf_win_window* window) {
    MSG msg;
    if (!window) return 1;
    for (;;) {
        BOOL got = GetMessageW(&msg, NULL, 0, 0);
        /* GetMessageW's third state is -1, and it leaves msg untouched. Reading
         * msg.wParam then would hand the shell a garbage exit code, which is
         * exactly the signal every headless check in this port relies on. */
        if (got == -1) return 73;
        if (got == 0) return (int)msg.wParam;
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
}

void spdf_win_window_destroy(spdf_win_window* window) {
    if (!window) return;
    discard_target(window);
    if (window->hwnd) {
        HWND hwnd = window->hwnd;
        window->hwnd = NULL;
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        DestroyWindow(hwnd);
    }
    free(window);
}
