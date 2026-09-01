#pragma once

/* Win32 message -> spdf_win_input translation, for spdf_win_window.cpp only.
 *
 * NOT A NEW LAYER. Every function here was in spdf_win_window.cpp and does
 * exactly what it did there; it moved out when routing the mouse through the
 * chrome pushed that file to its 500-line cap, and tools/file-size-limits.md
 * asks for an extracted file rather than a raised one. Same arrangement as
 * spdf_win_tabs_app.h and spdf_win_headless_viewport.h: header-only, included
 * from exactly one translation unit, AFTER `struct spdf_win_window` because it
 * dereferences it, and not part of the port's public surface.
 *
 * WHAT BELONGS HERE: turning a Win32 message into the small vocabulary
 * spdf_win_window.h declares -- filling in the fields every event carries,
 * converting WM_MOUSEWHEEL's screen point to client space, honouring the user's
 * SPI_GETWHEELSCROLLLINES, asking for a WM_MOUSELEAVE. WHAT DOES NOT: any
 * decision about what an event MEANS. That belongs to the caller, and the window
 * proc next door is the only thing that calls these.
 */

/* Fills in the fields every event carries and dispatches. Returns non-zero when
 * the handler changed the view, and invalidates when it did. */
static int dispatch(spdf_win_window* window, spdf_win_input* input) {
    RECT rc = {0, 0, 0, 0};

    if (!window->input_fn) return 0;
    GetClientRect(window->hwnd, &rc);
    input->view_px_w = (unsigned)(rc.right - rc.left);
    input->view_px_h = (unsigned)(rc.bottom - rc.top);
    input->mods = (GetKeyState(VK_CONTROL) < 0 ? SPDF_WIN_MOD_CTRL : 0u) |
                  (GetKeyState(VK_SHIFT) < 0 ? SPDF_WIN_MOD_SHIFT : 0u);
    /* So the handler can divide the client area exactly as the painter did. */
    input->dpi_scale = spdf_win_window_dpi_scale(window);
    if (!window->input_fn(window->user, input)) return 0;
    InvalidateRect(window->hwnd, NULL, FALSE);
    return 1;
}

/* One mouse event out to the handler, in CLIENT device pixels -- which is what
 * every mouse message but WM_MOUSEWHEEL carries (see on_wheel). */
static int dispatch_mouse(spdf_win_window* window, spdf_win_input_kind kind, int button, LPARAM lparam) {
    spdf_win_input input;
    if (kind == SPDF_WIN_INPUT_MOUSE_MOVE) {
        /* One WM_MOUSELEAVE per entry, or a hover highlight stays lit after the
         * pointer leaves. AppKit clears that free; Win32 must be asked, always. */
        TRACKMOUSEEVENT tme;
        tme.cbSize = sizeof(tme);
        tme.dwFlags = TME_LEAVE;
        tme.hwndTrack = window->hwnd;
        tme.dwHoverTime = 0;
        TrackMouseEvent(&tme);
    }
    memset(&input, 0, sizeof(input));
    input.kind = kind;
    input.button = button;
    input.x = (float)GET_X_LPARAM(lparam);
    input.y = (float)GET_Y_LPARAM(lparam);
    input.cursor = SPDF_WIN_CC_ARROW;
    return dispatch(window, &input);
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

/* End a press. `button` is the one that came up, or SPDF_WIN_CB_NONE for a
 * CANCELLATION -- the distinction spdf_win_window.h documents. */
static void end_press(spdf_win_window* window, int button, LPARAM lparam) {
    if (window->pressed == SPDF_WIN_CB_NONE) return;
    window->pressed = SPDF_WIN_CB_NONE;
    dispatch_mouse(window, SPDF_WIN_INPUT_MOUSE_UP, button, lparam);
    if (GetCapture() == window->hwnd) ReleaseCapture();
}
