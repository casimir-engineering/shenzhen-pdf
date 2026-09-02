/* ShenzhenPDF for Windows -- entry point.
 *
 *   ShenzhenPDF.exe [--dark|--light] [--page N] [--window ID | --new-window] [--state-dir DIR] [file.pdf]
 *       Opens a window on the continuous scrolling canvas, restoring the last
 *       session (or the window another process handed over as ID, or nothing).
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
#include "spdf_win_chrome_model.h" /* the chrome model the window paints */
#include "spdf_win_layout.h" /* SPDF_WIN_PAGE_MARGIN_* for the initial window size */
#include "spdf_win_open_app.h" /* the process opener every by-path open goes through, and its seam */
#include "spdf_win_paths.h"    /* spdf_win_paths_set_state_dir_override, for --state-dir */
#include "spdf_win_settings.h" /* settings.yaml: theme, panels, print, window size */
#include "spdf_win_tabs_app.h" /* the tab model, the session, and the glue to this canvas */
#include "spdf_win_usage.h"
#include "spdf_win_window.h"

#include <math.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")

/* `struct app`, the one window's state: in its own header since this file reached
 * its cap. Everything below depends on it. */
#include "spdf_win_app.h"

/* utf8_from_wide(), report(), open_document() and close_document(). Depends on
 * `struct app` above; everything below reports through it. */
#include "spdf_win_window_doc.h"

/* The window title, the selected tab with its remembered view, the frame, the
 * periodic session save and the opening size. Depends on `struct app` above
 * and on report(); everything below calls show_selected_tab() from it. */
#include "spdf_win_session_app.h"

/* The watcher's app half: a CHANGED reopens the tab in place, a MISSING marks
 * it, the first tick sweeps orphaned shadow copies. After show_selected_tab. */
#include "spdf_win_watch_app.h"

/* --- the window ---------------------------------------------------------- */

/* scene_for_window() -- the paint-time glue -- and the mouse routing. Both
 * depend on `struct app` and on show_selected_tab() above them, and both stay
 * out of this file because this file is at its 500-line cap and
 * tools/file-size-limits.md asks for an extracted file rather than a raised one.
 * Same arrangement as spdf_win_tabs_app.h and spdf_win_headless_viewport.h.
 *
 * The scene half comes FIRST: the input half calls two of its functions. */
#include "spdf_win_chrome_scene.h"
/* Presentation mode and full screen: what F5 and F11 do, and the pointer while
 * presenting. Before the tab strip's commands, which detach into new windows,
 * and before the router, which hands it the pointer. */
#include "spdf_win_window_presentation.h"
/* The tab strip's own commands -- select, close, open, the overflow menu,
 * drag-to-reorder, tear-off and new windows -- which chrome_perform() next door
 * calls. */
#include "spdf_win_chrome_tabs_ui.h"
/* The strip's hover preview, which the router's hover branch shows. */
#include "spdf_win_tabs_hover.h"
/* What the pointer does over the PAGE: select text, follow a link, or pan. */
#include "spdf_win_chrome_canvas_ui.h"
/* The find group, which field has the keyboard, and the sidebar's rows. */
#include "spdf_win_chrome_field_ui.h"
#include "spdf_win_chrome_actions.h"
/* The Markdown commands -- the A-/A+ text size and the image-cache arrival --
 * in the shape the command switch expects. After the tab strip and the
 * actions, whose show_selected_tab and spdf_win_tabs_app_remember it calls. */
#include "spdf_win_md_commands.h"
/* The keymap, the three typeable fields and the one command switch. LAST,
 * because it calls into all three above it. */
#include "spdf_win_chrome_commands.h"

/* --- headless ------------------------------------------------------------ */

#include "spdf_win_headless_viewport.h"

/* Depends on `app` and spdf_win_d2d above, so it is included here rather
 * than with the headers at the top. */
#include "spdf_win_headless.h"


int main(void) {
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return 70;

    /* THE ONE CALL, INSTALLED ONCE (spdf_win_open_app.h): from here on every
     * by-path open in the process -- the headless paths, the tab model, the
     * render workers, search, thumbnails, links, print -- opens a Markdown file
     * as pages, opens a read-only source's working copy when one exists, and
     * opens everything else exactly as before. Before the flag parse, because
     * --render-png and --render-window-png open too. */
    spdf_win_open_set_hook(spdf_win_open_app_document);

    app a;
    viewport_opts opts;
    int window_page = 0;
    /* Set by --dark or --light. Until one of them appears the theme is the
     * SYSTEM's, resolved below -- but only for the windowed path. */
    int theme_explicit = 0;
    /* --window / --new-window: how the windowed path finds its tabs. */
    spdf_win_tabs_app_restore restore = SPDF_WIN_TABS_APP_RESTORE_FIRST;
    memset(&a, 0, sizeof(a));
    memset(&opts, 0, sizeof(opts));
    a.render_flags = SPDF_RENDER_DEFAULT;
    /* Both side panels open, as macOS does for a new document
     * (ShenzhenPDFMac.mm:836-840). 0 width asks spdf_win_chrome.h for
     * its default. */
    a.show_sidebar = 1;
    a.show_minimap = 1;
    /* -1, not the 0 the memset left: 0 is a valid tab index, so a zeroed hover
     * state would draw the first tab hovered before the pointer has ever
     * entered the window. */
    a.hot_tab = -1;
    a.hot_close = -1;
    /* -1 for the same reason: 0 is a valid tab index and a valid drop slot, so a
     * zeroed drag state is a drag nobody started. */
    a.drag_tab = -1;
    a.drop_slot = -1;
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
            theme_explicit = 1;
            continue;
        }
        /* The counterpart, so a dark machine can still be told to open light and
         * a pixel case can pin either. */
        if (wcscmp(flag, L"--light") == 0) {
            a.render_flags &= ~(unsigned)(SPDF_RENDER_DARK_THEME | SPDF_RENDER_PRESERVE_IMAGES);
            theme_explicit = 1;
            continue;
        }
        /* Valueless, like --dark. Composes the window chrome into the headless
         * frame, so the whole window's pixels can be compared without a desktop. */
        if (wcscmp(flag, L"--chrome") == 0) {
            opts.chrome = 1;
            continue;
        }
        /* Valueless, like --chrome; pairs with --find below. */
        if (wcscmp(flag, L"--find-regex") == 0) {
            a.find_regex = 1;
            continue;
        }
        /* A fresh empty window with its own session id: what File > New Window
         * spawns. Restores nothing. */
        if (wcscmp(flag, L"--new-window") == 0) {
            restore = SPDF_WIN_TABS_APP_RESTORE_NONE;
            continue;
        }
        /* The chrome collapsed, as F5 leaves it, so the headless compose can
         * show the presentation frame with no desktop. */
        if (wcscmp(flag, L"--presentation") == 0) {
            spdf_win_chrome_presentation_set(1);
            a.presentation = 1;
            continue;
        }
        if (!value) return usage();
        /* The window another process handed over through session.yaml
         * (spdf_win_session_detach_tab): restore exactly that one. */
        if (wcscmp(flag, L"--window") == 0) {
            if (WideCharToMultiByte(CP_UTF8, 0, value, -1, a.window_id, (int)sizeof(a.window_id), NULL, NULL) <= 0)
                return usage();
            restore = SPDF_WIN_TABS_APP_RESTORE_ID;
            ++i;
            continue;
        }
        /* Where settings.yaml and session.yaml live, instead of %APPDATA%: the
         * explicit portable-mode switch spdf_win_paths.h reserves for the
         * frontend, and what lets a test drive a real window without touching
         * the reader's own state. Inherited by every window this one spawns. */
        if (wcscmp(flag, L"--state-dir") == 0) {
            char* dir = utf8_from_wide(value);
            if (!dir) return usage();
            spdf_win_paths_set_state_dir_override(dir);
            free(dir);
            wcsncpy_s(a.state_dir, value, _TRUNCATE);
            ++i;
            continue;
        }
        /* THE HEADLESS ROUTE TO A LIVE SEARCH, and the reason it exists.
         *
         * SPDF_FIND_QUERY used to be the only way to see the find chrome in a
         * frame, and this change deletes it -- the field is typeable now, and a
         * debugging hook that bypasses the real control is a hook that keeps
         * working after the real control has broken. But the session on this
         * machine can be locked, and then `--render-window-png --chrome` is the
         * ONLY way anyone can look at the window at all, so deleting the bridge
         * without replacing it would take the find chrome out of the one
         * verification path this port has.
         *
         * So it is a FLAG rather than an environment variable, and it goes
         * through spdf_win_find_set_query() -- the same function a keystroke
         * calls, on the same buffer, with the same conversion. It exercises the
         * real path instead of going round it. */
        if (wcscmp(flag, L"--find") == 0) wcsncpy_s(a.find_text, value, _TRUNCATE);
        else if (wcscmp(flag, L"--page") == 0) window_page = _wtoi(value);
        else if (wcscmp(flag, L"--zoom") == 0) opts.zoom = (float)_wtof(value);
        else if (wcscmp(flag, L"--scroll-x") == 0) opts.scroll_x = (float)_wtof(value);
        else if (wcscmp(flag, L"--scroll-y") == 0) opts.scroll_y = (float)_wtof(value);
        else if (wcscmp(flag, L"--dpi") == 0) opts.dpi_scale = (float)_wtof(value);
        else if (wcscmp(flag, L"--zoom-factor") == 0) opts.zoom_factor = (float)_wtof(value);
        else if (wcscmp(flag, L"--frames") == 0) opts.frames = _wtoi(value);
        else if (wcscmp(flag, L"--sidebar-section") == 0) opts.sidebar_section = _wtoi(value);
        else if (wcscmp(flag, L"--zoom-at") == 0) {
            wchar_t* comma = NULL;
            opts.zoom_at_x = (float)wcstod(value, &comma);
            opts.zoom_at_y = comma && *comma == L',' ? (float)wcstod(comma + 1, NULL) : 0.0f;
        } else if (wcscmp(flag, L"--fit") == 0) {
            if (wcscmp(value, L"width") == 0) opts.mode = SPDF_WIN_ZOOM_FIT_WIDTH;
            else if (wcscmp(value, L"height") == 0) opts.mode = SPDF_WIN_ZOOM_FIT_HEIGHT;
            else if (wcscmp(value, L"page") == 0) opts.mode = SPDF_WIN_ZOOM_FIT_PAGE;
            else if (wcscmp(value, L"actual") == 0) opts.mode = SPDF_WIN_ZOOM_ACTUAL;
            else return usage();
        } else {
            return usage();
        }
        ++i; /* consumed the value */
    }

    /* After the whole parse, so --find-regex may come on either side of --find.
     * A no-op with no query: spdf_win_find_set_query(NULL) creates no session. */
    a.find_caret = (int)wcslen(a.find_text);
    chrome_find_push(&a);

    int remaining = argc - i;
    /* The windowed path takes AT MOST one document, and may take none: a bare
     * launch restores the session, or opens an empty window that File > Open,
     * the strip's `+` and a dropped file can all fill. That is macOS's launch
     * behaviour, and it is what a double-click on the exe has to do -- until now
     * that printed this usage text and exited 64, so the app could only ever be
     * started from a command line that named a file. */
    if ((exact && remaining != 4) || (viewport && remaining != 5) || (!exact && !viewport && remaining > 1))
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
        /* The settings, then the theme -- BEFORE the canvas exists, which takes
         * its render flags at construction. Windowed path only; the headless
         * ones must not depend on a file or a registry value. Both points are
         * argued at spdf_win_system_prefers_dark() in spdf_win_window.h. */
        /* AND THE GPU DEVICE, ON A WORKER, FIRST. Nothing between here and the
         * first paint needs it and nothing here needs more than one core, so
         * the driver load overlaps the settings read, the session restore, the
         * document open and CreateWindowExW instead of following them. Windowed
         * path only: see spdf_win_gpu_prewarm.h. */
        spdf_win_gpu_prewarm_start(d2d);
        {
            const spdf_win_settings* settings = spdf_win_settings_shared();
            if (!theme_explicit) a.render_flags = app_initial_render_flags();
            a.show_sidebar = settings->default_sidebar_visible;
            a.show_minimap = settings->default_minimap_visible;
            a.sidebar_w = (float)settings->sidebar_width;
            a.minimap_w = (float)settings->minimap_width;
        }
        /* markdownFontScale, once, before the first Markdown tab is laid out;
         * the headless paths keep the default so a pixel case depends on no
         * file. */
        spdf_win_md_load_settings();

        spdf_win_enable_dark_menus(); /* before any menu exists */

        /* NULL when launched bare: utf8_from_wide(NULL) is NULL, and
         * spdf_win_tabs_app_start(NULL, ...) restores the saved session and
         * selects its tab, or leaves the model empty. */
        char* launch_path = remaining ? utf8_from_wide(argv[i]) : NULL;
        spdf_win_session_frame frame;
        spdf_win_enable_dpi_awareness();
        /* The watcher before the model: the launch document is opened by the
         * show below and its watch is registered by the open hook
         * (spdf_win_tabs_open.h), which needs somewhere to register it. */
        spdf_win_tabs_open_configure(app_on_watch, &a);
        spdf_win_tabs_open_start_watching();
        a.tabs = spdf_win_tabs_app_start(launch_path, restore, a.window_id, sizeof(a.window_id), &frame);
        free(launch_path);
        /* A NAMED document that will not open is an error the user must see. No
         * document at all is not: the window opens empty, with the chrome drawn
         * and a line saying how to open one (scene_for_window's no-canvas
         * branch), and every canvas call in the frontend tolerates a NULL
         * canvas -- which was checked rather than assumed. */
        if (!spdf_win_tabs_app_show(a.tabs, &a.canvas, a.render_flags, &a.pending_page) && remaining &&
            !spdf_win_tabs_open_cancelled()) {
            report(L"That document could not be opened.", true);
            rc = 1;
        } else {
            int client_w, client_h;
            if (window_page > 0) a.pending_page = window_page;
            initial_client_size(&client_w, &client_h);

            spdf_win_window* window = spdf_win_window_create(d2d, NULL, client_w, client_h, scene_for_window,
                                                            input_for_window, &a, err, sizeof(err));
            if (!window) {
                wchar_t message[400];
                _snwprintf_s(message, _TRUNCATE, L"Could not create the window: %hs", err);
                report(message, true);
                rc = 72;
            } else {
                /* All of these before the show: no placeholder title, no light
                 * caption, and no window that visibly grows a menu bar. */
                a.window = window;
                /* Password prompts from here on are modal to the window. */
                spdf_win_tabs_open_set_owner(spdf_win_window_native_handle(window));
                /* The frame the session remembered, clamped onto a monitor. */
                if (frame.w > 0 && frame.h > 0) spdf_win_window_set_frame(window, frame.x, frame.y, frame.w, frame.h);
                /* The restored tab's view -- fit mode, page, exact offset --
                 * placed now against the canvas rect the first paint will use,
                 * rather than the page alone on the first paint. */
                a.view_dpi = spdf_win_window_dpi_scale(window);
                app_canvas_viewport(&a, (unsigned)(client_w * a.view_dpi), (unsigned)(client_h * a.view_dpi),
                                    a.view_dpi, &a.view_w, &a.view_h);
                if (spdf_win_tabs_app_apply_view(a.tabs, a.canvas, a.view_w, a.view_h, a.view_dpi) &&
                    window_page <= 0)
                    a.pending_page = -1;
                app_restore_find_text(&a);
                sync_window_title(&a);
                spdf_win_window_set_tick(window, SPDF_WIN_SESSION_TICK_MS, app_tick);
                /* The deferred sweep of orphaned read-only copies, on its own
                 * one-shot rather than on the session tick -- see
                 * app_watch_sweep_once() for why thirty seconds was too late. */
                spdf_win_window_set_once(window, SPDF_WIN_WATCH_SWEEP_MS, app_watch_sweep_once);
                /* NO MENU BAR, deliberately: macOS's menus are in the system
                 * menu bar, not the window, and a Win32 bar cannot be themed
                 * dark. The same menu opens from the toolbar's `...` instead.
                 * The full reasoning, and how to put the bar back, is at
                 * spdf_win_menu_app_popup() in spdf_win_menu.h. */
                a.menu = NULL;
                spdf_win_window_set_dark_frame(window, (a.render_flags & SPDF_RENDER_DARK_THEME) != 0);
                spdf_win_window_show(window);
                /* The launch tab was shown before the window existed, so the
                 * one thing show_selected_tab() could not do for it -- start
                 * the fetch of a Markdown document's remote images -- is done
                 * here, now there is a window for the completion to reach. */
                spdf_win_md_command_after_open(&a, (HWND)spdf_win_window_native_handle(window));
                /* The taskbar identity (AppUserModelID, the window's icons) and the
                 * updater's timers, both after the show: nothing in either runs
                 * before first paint (spdf_win_about.h, spdf_win_updater.h). */
                spdf_win_about_apply_identity(spdf_win_window_native_handle(window));
                spdf_win_updater_start_background(spdf_win_window_native_handle(window));
                rc = spdf_win_window_run(window);
                /* What the session and the settings need from the window, read
                 * while it still exists. */
                a.exit_frame = app_session_frame(&a);
                app_settings_record(&a);
                a.window = NULL;
                /* DestroyWindow destroys the menu attached to the window, so
                 * there is nothing to free here -- only a pointer that must stop
                 * being followed. */
                a.menu = NULL;
                spdf_win_window_destroy(window);
            }
        }
        /* session.yaml, under the shared lock, then close what is still open.
         * The frame was read before the window went away, in app_exit_frame. */
        spdf_win_tabs_app_finish(a.tabs, a.canvas, a.window_id, &a.exit_frame);
        spdf_win_tabs_open_stop_watching(); /* after the model: no callback can reach a closed tab */
        a.canvas = NULL; /* the model closed it; close_document() must not */
    }

    close_document(&a);
    spdf_win_d2d_destroy(d2d);
    LocalFree(argv);
    return rc;
}
