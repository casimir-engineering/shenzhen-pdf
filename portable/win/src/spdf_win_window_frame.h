#pragma once

/* Window PROPERTIES -- the frame, the title, the dark caption, the menu bar --
 * for spdf_win_window.cpp only.
 *
 * NOT A NEW LAYER, and the same arrangement as spdf_win_window_input.h beside
 * it: header-only, included from exactly one translation unit, AFTER
 * `struct spdf_win_window` because it dereferences it, and not part of the
 * port's public surface. Every function here was in spdf_win_window.cpp and does
 * exactly what it did there; they moved out when the menu bar pushed that file
 * to its 500-line cap, and tools/file-size-limits.md asks for an extracted file
 * rather than a raised one.
 *
 * WHAT BELONGS HERE: things that are true of the WINDOW rather than of a frame
 * of pixels or of a message. All four are properties an HWND has and a WIC
 * bitmap cannot -- which is exactly the boundary spdf_win_window.h already draws
 * for the reading theme's two window-level halves, and the reason none of this
 * can sit behind spdf_win_paint().
 */

/* Grow the FRAME until the CLIENT area is the requested size at this window's
 * DPI and with whatever menu bar it now has. Idempotent, and a no-op at 96 dpi
 * with no menu -- which is exactly the case every headless comparison runs in. */
static void resize_to_client(spdf_win_window* window) {
    float s = spdf_win_window_dpi_scale(window);
    RECT rc = {0, 0, (LONG)(window->client_px_w * s), (LONG)(window->client_px_h * s)};
    DWORD style = (DWORD)GetWindowLongPtrW(window->hwnd, GWL_STYLE);
    if (!window->hwnd || window->client_px_w <= 0 || window->client_px_h <= 0) return;
    AdjustWindowRectEx(&rc, style ? style : WS_OVERLAPPEDWINDOW, GetMenu(window->hwnd) != NULL, 0);
    SetWindowPos(window->hwnd, NULL, 0, 0, rc.right - rc.left, rc.bottom - rc.top,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
}

void spdf_win_window_set_title(spdf_win_window* window, const wchar_t* title) {
    if (!window || !window->hwnd || !title) return;
    SetWindowTextW(window->hwnd, title);
}

/* DWMWA_USE_IMMERSIVE_DARK_MODE. The attribute number is 20 from Windows 10
 * 2004 (build 19041) onward; on 1809/1903/1909 the same undocumented attribute
 * was 19, and the two were never valid at the same time. So try 20 and fall back
 * to 19: DwmSetWindowAttribute rejects an out-of-range attribute with
 * E_INVALIDARG rather than succeeding quietly, which makes the fallback a real
 * runtime check instead of a guess from a version number. (This machine is
 * 10.0.26200, where 20 is the live one and 19 never runs.)
 *
 * GetProcAddress rather than a link-time import of dwmapi.lib, following
 * spdf_win_enable_dpi_awareness() above for exactly the same reason: one binary
 * that starts everywhere and simply looks slightly wrong on a Windows older than
 * the feature. LoadLibraryW, not GetModuleHandleW -- unlike user32.dll,
 * dwmapi.dll is not already in the process. */
typedef HRESULT(WINAPI* dwm_set_window_attribute_fn)(HWND, DWORD, LPCVOID, DWORD);

void spdf_win_window_set_dark_frame(spdf_win_window* window, int dark) {
    if (!window || !window->hwnd) return;
    HMODULE dwmapi = LoadLibraryW(L"dwmapi.dll");
    if (!dwmapi) return;
    dwm_set_window_attribute_fn set_attr =
        (dwm_set_window_attribute_fn)GetProcAddress(dwmapi, "DwmSetWindowAttribute");
    if (set_attr) {
        /* BOOL, 4 bytes: DWM validates the size and fails a plain `int` on some
         * builds. */
        BOOL on = dark ? TRUE : FALSE;
        if (FAILED(set_attr(window->hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &on, sizeof(on))))
            set_attr(window->hwnd, 19 /* the same attribute pre-2004 */, &on, sizeof(on));
    }
    FreeLibrary(dwmapi);
}

/* MAKE MENUS AND OTHER COMMON CONTROLS FOLLOW DARK MODE.
 *
 * A Win32 menu bar and every TrackPopupMenu are drawn by the system in the
 * light palette unless the process opts in, and there is no documented way to
 * ask. The result on a dark desktop is a bright strip between a dark caption
 * and dark chrome, which reads as a second title bar -- reported from actual
 * use as "a double top bar like it's a window inside of a window".
 *
 * uxtheme.dll's SetPreferredAppMode is ordinal 135 and has no exported name.
 * That is what every Windows app that themes its menus uses, because it is the
 * only thing that works; it is also why this is wrapped in as much caution as
 * it is:
 *
 *   - Looked up BY ORDINAL, which is what it is published as. If a future
 *     Windows renumbers or removes it, GetProcAddress returns NULL and the app
 *     keeps its light menus. That is a cosmetic loss, never a failure.
 *   - Version-gated to build 18362 (1903) and later, where the entry point
 *     appeared. On anything older the ordinal may point at something else
 *     entirely, so it is not called at all.
 *   - Return value ignored on purpose: it hands back the PREVIOUS mode, and
 *     there is nothing useful to do with it.
 *
 * The alternative was owner-drawing the whole menu bar, which means taking over
 * measurement, keyboard navigation and accessibility for a strip this app may
 * not even keep. Not worth it for the same pixels.
 *
 * FlushMenuThemes() afterwards, because menus created before the mode changed
 * keep their old theme otherwise -- and the menu bar is created right after
 * this runs. */
void spdf_win_enable_dark_menus(void) {
    /* PreferredAppMode: 0 Default, 1 AllowDark, 2 ForceDark, 3 ForceLight. */
    typedef int(WINAPI * set_preferred_app_mode_fn)(int);
    typedef void(WINAPI * flush_menu_themes_fn)(void);
    HMODULE uxtheme;
    set_preferred_app_mode_fn set_mode;
    flush_menu_themes_fn flush;
    DWORD build = 0;

    /* RtlGetNtVersionNumbers rather than GetVersionEx, which lies to
     * unmanifested processes and would report 6.2 here. */
    {
        typedef void(WINAPI * get_version_fn)(DWORD*, DWORD*, DWORD*);
        HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
        get_version_fn get_version =
            ntdll ? (get_version_fn)GetProcAddress(ntdll, "RtlGetNtVersionNumbers") : NULL;
        DWORD major = 0, minor = 0;
        if (get_version) {
            get_version(&major, &minor, &build);
            build &= 0x0FFFFFFF; /* the top nibble is a flag, not part of the number */
        }
        if (major < 10 || build < 18362) return;
    }

    uxtheme = LoadLibraryW(L"uxtheme.dll");
    if (!uxtheme) return;
    set_mode = (set_preferred_app_mode_fn)GetProcAddress(uxtheme, (LPCSTR)135);
    if (set_mode) {
        /* AllowDark, not ForceDark: the app then follows the SYSTEM setting, so
         * a user who flips Windows back to light gets light menus without the
         * app having to notice. */
        set_mode(1);
        flush = (flush_menu_themes_fn)GetProcAddress(uxtheme, (LPCSTR)136);
        if (flush) flush();
    }
    /* uxtheme stays loaded deliberately: the mode is process-wide and menus are
     * created later, so unloading here could take the theming with it. */
}

int spdf_win_system_prefers_dark(void) {
    /* AppsUseLightTheme is the APP theme; SystemUsesLightTheme next to it is the
     * taskbar's, and the two are independently settable in Windows Settings. A
     * document reader is an app, so it follows the app one.
     *
     * RRF_RT_REG_DWORD makes the type part of the query rather than something to
     * check afterwards, and a missing key leaves `light` at its initial 1 --
     * which is what Windows itself assumes when the value has never been
     * written. So a machine that has never touched the setting reads as light,
     * not as garbage. */
    DWORD light = 1;
    DWORD size = sizeof(light);
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                     L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, &light, &size) != ERROR_SUCCESS)
        return 0;
    return light ? 0 : 1;
}

void spdf_win_window_set_menu(spdf_win_window* window, void* hmenu) {
    if (!window || !window->hwnd || !hmenu) return;
    if (!SetMenu(window->hwnd, (HMENU)hmenu)) return;
    DrawMenuBar(window->hwnd);
    /* The frame just grew a menu bar out of the client area's height. Re-run the
     * sizing that spdf_win_window_create() did, now with bMenu TRUE, so the
     * CLIENT area is still the size that was asked for -- otherwise the first
     * document opens in a window one menu bar shorter than every offscreen
     * render this port compares against. */
    resize_to_client(window);
}

void* spdf_win_window_native_handle(spdf_win_window* window) {
    return window ? (void*)window->hwnd : NULL;
}
