/* Win32 window + message pump. See spdf_win_window.h for the layering rule.
 *
 * Every Win32 call here is an explicit *W call. guest-build.cmd does not
 * define UNICODE, so the undecorated names would silently resolve to the ANSI
 * variants and mangle every non-ASCII document title -- the exact class of bug
 * windows-port-plan.md sec 2.2 warns about ("Call *W APIs exclusively; never
 * *A").
 */
#include "spdf_win_window.h"

/* For SPDF_WIN_MENU_ID_BASE alone. WM_COMMAND's low word is a number the two
 * files have to agree about; the table it indexes stays entirely next door. */
#include "spdf_win_menu.h"
/* For spdf_win_chrome_caption_set_state() alone: the three caption facts only
 * an HWND knows (maximized, hovered button, held button), pushed to the model
 * the chrome painter reads. See spdf_win_window_caption.h. */
#include "spdf_win_chrome_model.h"

#include <windowsx.h> /* GET_X_LPARAM / GET_Y_LPARAM */
#include <shellapi.h> /* DragAcceptFiles / DragQueryFileW / DragFinish */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
    /* The CLIENT area that was asked for, in 96-dpi pixels. Kept because two
     * later events -- the DPI of the monitor the window actually landed on, and
     * a menu bar being installed -- both change the FRAME needed to deliver it,
     * and neither can recover the request from the window. */
    int client_px_w;
    int client_px_h;
    /* The multi-click series in progress: how many presses have landed in the
     * same place in a row, and when and where the last one was. See
     * next_click_count() in spdf_win_window_input.h. */
    unsigned click_count;
    DWORD last_click_time;
    LONG last_click_x;
    LONG last_click_y;

    /* Which button, if any, is held with the capture. The authority, not
     * GetCapture(): a capture can be taken away (an Alt+Tab, a system modal) and
     * the WM_CAPTURECHANGED that follows must end the gesture, or the next mouse
     * move a second later applies the distance travelled in between. WHAT the
     * gesture means is the caller's now; the capture is the Win32 half. */
    int pressed; /* spdf_win_chrome_button; SPDF_WIN_CB_NONE when nothing is */

    /* THE CAPTION IS OURS (spdf_win_window_caption.h). Whether the window is
     * maximized, and which of the three drawn caption buttons the pointer is over
     * or holding, as spdf_win_caption_button. Mirrored into the chrome model
     * through spdf_win_chrome_caption_set_state() whenever any of them changes. */
    int maximized;
    int caption_hot;
    int caption_pressed;

    /* FULL SCREEN (spdf_win_window_frame.h). The placement to go back to, valid
     * only while `fullscreen` is set. */
    int fullscreen;
    WINDOWPLACEMENT placement;

    /* The periodic tick (spdf_win_window_set_tick), or NULL. */
    spdf_win_tick_fn tick_fn;

    /* THE TOOLTIP (spdf_win_window_tooltip.h): the control, created on first
     * use, and the text waiting for the show delay to elapse. */
    HWND tooltip;
    wchar_t tooltip_text[512];
    int tooltip_x;
    int tooltip_y;
};

/* Timer ids. WM_TIMER carries the id in wParam; these two are the only timers
 * this window sets. */
#define SPDF_WIN_TIMER_TICK 1
#define SPDF_WIN_TIMER_TOOLTIP 2

float spdf_win_window_dpi_scale(const spdf_win_window* window) {
    if (!window || window->dpi == 0) return 1.0f;
    return (float)window->dpi / (float)USER_DEFAULT_SCREEN_DPI;
}

/* The HWND render target and paint(). Depends on `struct spdf_win_window`
 * above, hence the position. */
#include "spdf_win_window_target.h"

/* Message-to-input translation: dispatch(), dispatch_mouse(), on_wheel() and
 * end_press(). Depends on `struct spdf_win_window` above, hence the position. */
#include "spdf_win_window_input.h"

/* The caption as client area: WM_NCCALCSIZE, WM_NCHITTEST, the caption buttons.
 * Depends on dispatch() above, hence the position. */
#include "spdf_win_window_caption.h"

/* The frame, the title, the dark frame, full screen and the menu bar. Depends
 * on frame_extents() above, hence the position. */
#include "spdf_win_window_frame.h"

/* The tab strip's hover preview. Depends on `struct spdf_win_window` and the
 * timer ids above. */
#include "spdf_win_window_tooltip.h"

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
            sync_maximized(window);
            return 0;
        /* THE CAPTION IS CLIENT AREA. See spdf_win_window_caption.h for all
         * six of these; the first two are what make the strip the title bar,
         * the other four are the three buttons the chrome draws. */
        case WM_NCCALCSIZE:
            return nc_calc_size(window, wparam, lparam);
        case WM_NCHITTEST:
            return nc_hit_test(window, wparam, lparam);
        case WM_NCMOUSEMOVE:
            nc_mouse_move(window, wparam);
            break;
        case WM_NCMOUSELEAVE:
            nc_mouse_leave(window);
            break;
        case WM_NCLBUTTONDOWN:
        case WM_NCLBUTTONDBLCLK:
            if (nc_lbutton_down(window, wparam)) return 0;
            break;
        case WM_NCLBUTTONUP:
            if (nc_lbutton_up(window, wparam)) return 0;
            break;
        case WM_MOUSEWHEEL:
            on_wheel(window, wparam, lparam, false);
            return 0;
        case WM_MOUSEHWHEEL:
            on_wheel(window, wparam, lparam, true);
            return 0;
        /* WM_LBUTTONDBLCLK IS AN ORDINARY PRESS HERE, and it exists at all
         * because the class asks for CS_DBLCLKS. Windows delivers the second
         * click of a double as this message INSTEAD of a WM_LBUTTONDOWN, so a
         * window that does not handle it loses every even-numbered click -- a
         * double-click to select a word would drop half of itself. What makes it
         * a double rather than a single is the count, which next_click_count()
         * has already worked out. */
        case WM_LBUTTONDOWN:
        case WM_LBUTTONDBLCLK:
        case WM_MBUTTONDOWN:
            tooltip_hide(window); /* a press ends a hover */
            /* Capture first, so a handler that starts a drag has the pointer. */
            window->pressed = msg == WM_MBUTTONDOWN ? SPDF_WIN_CB_MIDDLE : SPDF_WIN_CB_LEFT;
            if (msg != WM_MBUTTONDOWN) next_click_count(window, lparam);
            SetCapture(hwnd);
            SetFocus(hwnd);
            dispatch_mouse(window, SPDF_WIN_INPUT_MOUSE_DOWN, window->pressed, lparam);
            return 0;
        case WM_MOUSEMOVE:
            /* The pointer is in the client, so no caption button is under it,
             * whatever WM_NCMOUSELEAVE did or did not say. */
            if (window->caption_hot != SPDF_WIN_CAPTION_NONE)
                caption_set(window, SPDF_WIN_CAPTION_NONE, window->caption_pressed);
            /* Unconditionally, not only while a button is down: hover state is
             * what lights the tab strip, and the handler decides if it changed. */
            dispatch_mouse(window, SPDF_WIN_INPUT_MOUSE_MOVE, window->pressed, lparam);
            return 0;
        case WM_MOUSELEAVE:
            /* A position no chrome contains, so the router clears every hot flag.
             * Not while a button is down: the capture keeps the gesture alive
             * outside the window and (-1, -1) would pan the whole way there. */
            if (window->pressed == SPDF_WIN_CB_NONE)
                dispatch_mouse(window, SPDF_WIN_INPUT_MOUSE_MOVE, SPDF_WIN_CB_NONE, (LPARAM)-1);
            tooltip_hide(window);
            return 0;
        /* The right button, as SPDF_WIN_INPUT_CONTEXT. No capture, no release:
         * see the enum. Consumed whether or not the handler wanted it -- with no
         * menu bar there is no WM_CONTEXTMENU anyone is waiting for. */
        case WM_RBUTTONDOWN:
            SetFocus(hwnd);
            dispatch_mouse(window, SPDF_WIN_INPUT_CONTEXT, SPDF_WIN_CB_NONE, lparam);
            return 0;
        case WM_TIMER:
            if (wparam == SPDF_WIN_TIMER_TICK && window->tick_fn) window->tick_fn(window->user);
            else if (wparam == SPDF_WIN_TIMER_TOOLTIP) tooltip_fire(window);
            return 0;
        case WM_LBUTTONUP:
            /* A caption button pressed and released over the client is a press
             * abandoned, not a click. */
            if (window->caption_pressed != SPDF_WIN_CAPTION_NONE)
                caption_set(window, SPDF_WIN_CAPTION_NONE, SPDF_WIN_CAPTION_NONE);
            end_press(window, SPDF_WIN_CB_LEFT, lparam);
            return 0;
        case WM_MBUTTONUP:
            end_press(window, SPDF_WIN_CB_MIDDLE, lparam);
            return 0;
        case WM_CAPTURECHANGED:
            /* lparam is the window that TOOK the capture, not a position, and
             * SPDF_WIN_CB_NONE already says "cancelled", not "clicked". */
            end_press(window, SPDF_WIN_CB_NONE, 0);
            return 0;
        case WM_SETCURSOR:
            if (LOWORD(lparam) == HTCLIENT) {
                /* Ask the handler: the answer is about the chrome, or during a
                 * drag about the drag. WM_SETCURSOR carries no position. */
                POINT pt = {0, 0};
                spdf_win_input query;
                UINT id = 32512; /* IDC_ARROW */
                memset(&query, 0, sizeof(query));
                query.kind = SPDF_WIN_INPUT_CURSOR;
                query.button = window->pressed;
                query.cursor = SPDF_WIN_CC_ARROW;
                if (GetCursorPos(&pt) && ScreenToClient(hwnd, &pt)) {
                    query.x = (float)pt.x;
                    query.y = (float)pt.y;
                    dispatch(window, &query);
                }
                if (query.cursor == SPDF_WIN_CC_SIZEWE) id = 32644;       /* IDC_SIZEWE */
                else if (query.cursor == SPDF_WIN_CC_SIZEALL) id = 32646; /* IDC_SIZEALL */
                else if (query.cursor == SPDF_WIN_CC_IBEAM) id = 32513;   /* IDC_IBEAM */
                else if (query.cursor == SPDF_WIN_CC_HAND) id = 32649;    /* IDC_HAND */
                SetCursor(LoadCursorW(NULL, MAKEINTRESOURCEW(id)));
                return TRUE;
            }
            break;
        case WM_GETMINMAXINFO:
            min_track_size(window, (MINMAXINFO*)lparam);
            return 0;
        case WM_DPICHANGED: {
            /* Windows hands us the rectangle the window should occupy on the
             * monitor it just moved to. Honouring it is what makes a drag
             * between a 1x and a 2x display keep the window physically the
             * same size instead of doubling. */
            window->dpi = HIWORD(wparam);
            RECT* suggested = (RECT*)lparam;
            SetWindowPos(hwnd, NULL, suggested->left, suggested->top, suggested->right - suggested->left,
                         suggested->bottom - suggested->top, SWP_NOZORDER | SWP_NOACTIVATE);
            extend_frame_into_strip(window); /* the caption height changed with the DPI */
            InvalidateRect(hwnd, NULL, FALSE);
            return 0;
        }
        case WM_COMMAND:
            /* A menu item, and nothing else: this window has no child controls,
             * so a WM_COMMAND with a non-zero lParam (a control) or a high word
             * of 1 (an accelerator table, which this port does not use -- see
             * spdf_win_menu.h) is not ours. */
            if (lparam == 0 && HIWORD(wparam) == 0 && LOWORD(wparam) >= SPDF_WIN_MENU_ID_BASE) {
                dispatch_value(window, SPDF_WIN_INPUT_COMMAND, (unsigned)(LOWORD(wparam) - SPDF_WIN_MENU_ID_BASE));
                return 0;
            }
            break;
        case WM_CHAR:
            /* Always consumed, handled or not. DefWindowProc does nothing with a
             * WM_CHAR for a window with no child controls, and a key the handler
             * declined is a key nobody wanted -- passing it on would only reach
             * the default beep. Menu mnemonics arrive as WM_SYSCHAR, which is
             * untouched. */
            dispatch_value(window, SPDF_WIN_INPUT_CHAR, (unsigned)wparam);
            return 0;
        case WM_DROPFILES:
            dispatch_drop(window, wparam);
            return 0;
        /* WM_SYSKEYDOWN as well as WM_KEYDOWN, because Alt+key arrives as the
         * former and macOS puts page navigation on Option+arrows. Anything the
         * handler declines falls through to DefWindowProc, which is what keeps
         * Alt+F opening the File menu and Alt+F4 closing the window. */
        case WM_SYSKEYDOWN:
        case WM_KEYDOWN: {
            spdf_win_input input;
            memset(&input, 0, sizeof(input));
            input.kind = SPDF_WIN_INPUT_KEY;
            input.key = (unsigned)wparam;
            if (dispatch(window, &input)) return 0;
            /* AN ESCAPE NOBODY WANTED. It used to close the window from here,
             * which macOS never does and which bit anyone who cancelled a search
             * twice (portable/docs/windows-feature-matrix.md, gap 2). Now it
             * leaves full screen when the window is in it -- the one key policy
             * this file holds, argued at spdf_win_window_set_fullscreen() -- and
             * otherwise does nothing at all. Pinned by window_keys_test.c. */
            if (msg == WM_KEYDOWN && wparam == VK_ESCAPE) {
                if (spdf_win_window_escape_leaves_fullscreen(window->fullscreen))
                    dispatch_value(window, SPDF_WIN_INPUT_COMMAND, (unsigned)SPDF_WIN_CMD_FULLSCREEN);
                return 0;
            }
            break;
        }
        case WM_DESTROY:
            window->pressed = SPDF_WIN_CB_NONE;
            if (GetCapture() == hwnd) ReleaseCapture();
            /* The tooltip is OWNED by this window, so Windows destroys it with
             * us; only the handle must stop being followed. */
            window->tooltip = NULL;
            spdf_win_window_prevent_sleep(0);
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
    /* CS_DBLCLKS: without it Windows never sends WM_LBUTTONDBLCLK and there is
     * no way to know a click was a double at all -- double-click-to-select-a-
     * word is not implementable without it, and adding it later silently changes
     * which message every second click arrives as. */
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
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
    window->client_px_w = client_px_w;
    window->client_px_h = client_px_h;
    resize_to_client(window);
    /* The strip is the title bar: hand DWM the caption region so it keeps
     * drawing the shadow, the rounded corners and the frame around a window
     * whose caption is now client area (spdf_win_window_caption.h). */
    extend_frame_into_strip(window);
    /* THE DROP TARGET. One call, and the only reason it is not in
     * register_class() is that it is a property of the window rather than of the
     * class. WM_DROPFILES is the old shell drop protocol rather than
     * IDropTarget: it delivers exactly what this app wants (a list of paths) and
     * costs no COM, no reference counting and no second object to keep alive. */
    DragAcceptFiles(window->hwnd, TRUE);
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

void spdf_win_window_set_tick(spdf_win_window* window, unsigned ms, spdf_win_tick_fn fn) {
    if (!window || !window->hwnd) return;
    window->tick_fn = ms ? fn : NULL;
    if (ms && fn) SetTimer(window->hwnd, SPDF_WIN_TIMER_TICK, ms, NULL);
    else KillTimer(window->hwnd, SPDF_WIN_TIMER_TICK);
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
