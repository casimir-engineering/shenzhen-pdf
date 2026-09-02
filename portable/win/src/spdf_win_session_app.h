#pragma once

/* spdf_win_session_app.h -- the app's half of the session and the settings:
 * the window title, showing the selected tab with its remembered view, the
 * frame, the periodic save, and the opening size.
 *
 * Header-only and included from spdf_win_main.cpp immediately after `struct
 * app` and before every other glue header, because show_selected_tab() is what
 * spdf_win_chrome_tabs_ui.h and spdf_win_chrome_commands.h call. Same
 * arrangement as spdf_win_tabs_app.h beside it, and split from
 * spdf_win_main.cpp for the reason that file keeps giving: it is at its
 * 500-line cap and tools/file-size-limits.md asks for an extracted file rather
 * than a raised one. Not part of the port's public surface.
 *
 * WHEN THE SESSION IS WRITTEN. It used to be written once, at exit; a crash or
 * a power cut lost every tab opened since launch. Now app_session_save() runs
 * on every change to the set of tabs (spdf_win_chrome_tabs_ui.h), on the
 * window's tick (spdf_win_window_set_tick, SPDF_WIN_SESSION_TICK_MS) and at
 * exit. The write itself is cheap and idempotent -- the state layer compares
 * bytes and skips a no-op save (spdf_win_state.h) -- and it runs under the
 * cross-process lock, so two windows saving at once cannot lose each other.
 */

/* Half a minute: often enough that a crash costs little, seldom enough that a
 * reader scrolling through a document does not churn the disk. */
#define SPDF_WIN_SESSION_TICK_MS 30000

/* macOS titles the window "<display name> - Shenzhen PDF", and the bare product
 * name with no document (ShenzhenPDFMac.mm:8615, :10582; :8985, :9168). Same two
 * strings here, so the two apps read alike in a task switcher -- and so the title
 * stops naming the launch document forever, which is what it did while
 * CreateWindowExW's argument was the only title a session ever got.
 *
 * The display name is the tab's own title, i.e. the path's last component. The
 * strip shows the disambiguated form (spdf_win_tabs_names.h); the title bar is
 * invisible on this window and only the taskbar and Alt-Tab read it, so the
 * plain leaf is enough there. */
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

/* THE TAB'S QUERY BECOMES THE FIND FIELD'S. Each tab remembers its own
 * (spdf_win_tab_view::search_text); on show the field and the process-wide find
 * bridge are both set from it, so a Ctrl+Tab brings back the query the reader
 * left in that document -- and clears the field for a tab that had none.
 * Through spdf_win_find_set_query() directly rather than chrome_find_push(),
 * which is defined in a header included after this one. */
static void app_restore_find_text(app* a) {
    const spdf_win_tab_view* view =
        a->tabs ? spdf_win_tabs_view_const(a->tabs, spdf_win_tabs_selected_index(a->tabs)) : NULL;
    a->find_text[0] = L'\0';
    if (view && view->search_text[0] &&
        MultiByteToWideChar(CP_UTF8, 0, view->search_text, -1, a->find_text,
                            (int)(sizeof(a->find_text) / sizeof(a->find_text[0]))) <= 0)
        a->find_text[0] = L'\0';
    a->find_caret = (int)wcslen(a->find_text);
    spdf_win_find_set_query(a->find_text[0] ? a->find_text : NULL, a->find_regex);
}

/* Point the canvas at the newly selected tab, put the tab's remembered view
 * back on it, restore its query AND retitle the window: every caller wants all
 * of it, and doing only the first was the defect being fixed. The view is
 * placed against the canvas viewport the last input event or the launch laid
 * the chrome out against (a->view_w/h); with none known yet, the first paint's
 * pending_page path places the page alone. */
/* Defined in spdf_win_md_commands.h, which spdf_win_main.cpp includes after this
 * header: a Markdown tab whose open recorded remote images not yet in the cache
 * starts fetching them; a no-op on a PDF tab and with nothing pending. */
static void spdf_win_md_command_after_open(app* a, HWND window);

static int show_selected_tab(app* a) {
    int shown = spdf_win_tabs_app_show(a->tabs, &a->canvas, a->render_flags, &a->pending_page);
    if (shown && spdf_win_tabs_app_apply_view(a->tabs, a->canvas, a->view_w, a->view_h, a->view_dpi))
        a->pending_page = -1;
    app_restore_find_text(a);
    sync_window_title(a);
    /* Every show goes through here -- open, switch, restore, reload, a theme
     * rebuild -- so this is the one place a Markdown tab's images are asked
     * for. The completion message re-shows the tab (spdf_win_md_commands.h). */
    if (shown && a->window) spdf_win_md_command_after_open(a, (HWND)spdf_win_window_native_handle(a->window));
    return shown;
}

/* The window's frame for the session, or a zero frame when there is no window
 * (the headless paths, or after it closed). */
static spdf_win_session_frame app_session_frame(app* a) {
    spdf_win_session_frame f;
    memset(&f, 0, sizeof(f));
    if (a->window) spdf_win_window_get_frame(a->window, &f.x, &f.y, &f.w, &f.h);
    return f;
}

/* Write this window into session.yaml now: the reader's place in the selected
 * tab, every tab's metadata, and the frame. */
static int app_session_save(app* a) {
    spdf_win_session_frame f;
    if (!a->tabs) return 0;
    spdf_win_tabs_app_remember(a->tabs, a->canvas);
    f = app_session_frame(a);
    return spdf_win_session_save_ex(a->tabs, a->window_id, &f);
}

/* Preferences that are the window's to record: the two panel widths the reader
 * dragged, and the content size, as the mac writes them (windowSize is a
 * CONTENT size in points, :1798). Committed to settings.yaml at exit and on the
 * tick; the state layer skips a save whose bytes are unchanged. */
static void app_settings_record(app* a) {
    spdf_win_settings* s = spdf_win_settings_shared();
    if (a->sidebar_w > 0.0f) s->sidebar_width = (int)(a->sidebar_w + 0.5f);
    if (a->minimap_w > 0.0f) s->minimap_width = (double)a->minimap_w;
    if (a->window && !a->fullscreen && a->view_dpi > 0.0f) {
        RECT rc;
        if (GetClientRect((HWND)spdf_win_window_native_handle(a->window), &rc)) {
            s->window_width = (int)((float)(rc.right - rc.left) / a->view_dpi + 0.5f);
            s->window_height = (int)((float)(rc.bottom - rc.top) / a->view_dpi + 0.5f);
        }
    }
    spdf_win_settings_commit();
}

static void app_tick(void* user) {
    app* a = (app*)user;
    app_session_save(a);
    app_settings_record(a);
}

/* THE WINDOW'S OPENING SIZE, AND ITS FLOOR.
 *
 * This used to derive the size from page 0 at 100% -- page width plus margins,
 * shrunk to fit the work area, with NO minimum. On golden.pdf that opens a
 * 244 x 286 window: narrower than its own caption buttons, and far narrower
 * than the 84 pt of chrome the window now has to hold. macOS never did this. It
 * opens every document window at a fixed 1120 x 800 and clamps a restored size
 * into [560 … min(2200, screenW − 40)] x [380 … min(1600, screenH − 40)]
 * (ShenzhenPDFMac.mm:2912-2938, :69-70, :189-196), so a small page gets a
 * normal window with a small page in it rather than a window the size of the
 * page. The constants live in spdf_win_chrome.h with the rest of the metrics;
 * the size itself is settings.yaml's windowSize, which is where the mac keeps
 * it too, so a reader who made the window bigger gets it back that size.
 *
 * The floor is enforced twice, deliberately: here, so the window opens above it,
 * and in WM_GETMINMAXINFO, so the user cannot drag below it afterwards. Only the
 * second is load-bearing against a user; the first is what stops the app from
 * doing it to itself.
 *
 * Done before the window exists, so it uses the system DPI; WM_DPICHANGED
 * corrects anything the real monitor disagrees with. */
#define SPDF_WIN_RESTORE_MAX_W 2200.0f /* :189-196 */
#define SPDF_WIN_RESTORE_MAX_H 1600.0f
#define SPDF_WIN_SCREEN_INSET 40.0f

static float clamp_content(float want, float lo, float hi, float screen) {
    float top = screen - SPDF_WIN_SCREEN_INSET;
    if (top < hi) hi = top;
    if (hi < lo) hi = lo; /* a screen too small to satisfy both: the floor wins */
    if (want < lo) want = lo;
    if (want > hi) want = hi;
    return want;
}

static void initial_client_size(int* out_w, int* out_h) {
    const spdf_win_settings* s = spdf_win_settings_shared();
    RECT work = {0, 0, 1280, 800};
    float want_w = s->window_width > 0 ? (float)s->window_width : (float)SPDF_WIN_CHROME_DEFAULT_CONTENT_W;
    float want_h = s->window_height > 0 ? (float)s->window_height : (float)SPDF_WIN_CHROME_DEFAULT_CONTENT_H;
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    *out_w = (int)clamp_content(want_w, (float)SPDF_WIN_CHROME_MIN_CONTENT_W, SPDF_WIN_RESTORE_MAX_W,
                                (float)(work.right - work.left));
    *out_h = (int)clamp_content(want_h, (float)SPDF_WIN_CHROME_MIN_CONTENT_H, SPDF_WIN_RESTORE_MAX_H,
                                (float)(work.bottom - work.top));
}

/* The reading theme a window STARTS in, from the settings and then the system:
 * an expressed preference wins (the reader toggled it once), else the system's
 * app theme (spdf_win_system_prefers_dark). Keep Image Colors rides along as
 * the mac composes it (SPDFMacReadingThemeIntegration.mm:41). Windowed path
 * only, and BEFORE the canvas exists, for the two reasons spdf_win_window.h
 * gives at spdf_win_system_prefers_dark(). */
static unsigned app_initial_render_flags(void) {
    const spdf_win_settings* s = spdf_win_settings_shared();
    int dark = s->theme == SPDF_WIN_THEME_DARK ? 1 : s->theme == SPDF_WIN_THEME_LIGHT ? 0 : spdf_win_system_prefers_dark();
    unsigned flags = SPDF_RENDER_DEFAULT;
    if (dark) flags |= SPDF_RENDER_DARK_THEME | (s->dark_theme_preserves_images ? SPDF_RENDER_PRESERVE_IMAGES : 0u);
    return flags;
}
