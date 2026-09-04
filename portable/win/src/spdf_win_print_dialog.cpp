/* spdf_win_print_dialog.cpp — the WINDOW half of the in-app print dialog. Why
 * it exists at all is spdf_win_print_dialog.h; the spooler half beside it is
 * spdf_win_print_dialog_run.cpp.
 *
 * NO RESOURCE SCRIPT, NO DIALOG TEMPLATE, for the reason
 * spdf_win_properties_dialog.cpp gives: the port has no .rc for anything but
 * the app's own icon and manifest, and build-native.cmd discovers .c/.cpp and
 * nothing else. So this is a plain window with fifteen child controls and a
 * local modal loop -- which is also what lets it disable exactly one parent
 * window instead of the whole thread, in an app that is tabbed and
 * multi-window.
 *
 * IsDialogMessageW IS IN THE LOOP, unlike in the About box or the properties
 * panel. Those have two controls each and Tab has nowhere to go; this one has a
 * combo, six radios, three fields and two buttons, and a print dialog that
 * cannot be driven from the keyboard is not finished. Enter and Esc are handled
 * BEFORE it: with no dialog manager underneath there is no default-id for
 * IsDialogMessage to find, and Enter in an ES_NUMBER field would otherwise beep.
 *
 * DARK MODE STRIPS THE VISUAL STYLE FROM THE CONTROLS, and that is deliberate.
 * A themed BS_AUTORADIOBUTTON paints its own label through uxtheme and ignores
 * SetTextColor, so dark-on-dark is what a themed radio gives on a dark panel --
 * the label simply disappears. SetWindowTheme(h, L"", L"") turns one control
 * back into a classic one that honours WM_CTLCOLOR*, which is plainer than
 * Windows 11 but readable, and readable wins. In LIGHT mode nothing is
 * stripped, so the normal case looks like a Windows dialog.
 */

#include "spdf_win_print_dialog.h"

#include "spdf_win_about.h"        /* spdf_win_about_dark_caption */
#include "spdf_win_chrome_theme.h" /* the port's own palette */

#include <uxtheme.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "uxtheme.lib")

#define PD_ID_PRINTER 1201
#define PD_ID_PROPS 1202
/* 1203-1205 are the range radios in spdf_win_print_range_mode order and
 * 1209-1211 the scaling radios in spdf_win_print_scaling_mode order, so
 * (id - first) IS the mode in both cases. */
#define PD_ID_RANGE_ALL 1203
#define PD_ID_RANGE_CURRENT 1204
#define PD_ID_RANGE_FROMTO 1205
#define PD_ID_FROM 1206
#define PD_ID_TO 1207
#define PD_ID_COPIES 1208
#define PD_ID_SCALE_FIT 1209
#define PD_ID_SCALE_ACTUAL 1210
#define PD_ID_SCALE_CUSTOM 1211
#define PD_ID_PERCENT 1212
#define PD_ID_PRINT 1213
#define PD_ID_CANCEL 1214
#define PD_ID_NOTE 1215

#define PD_WIDTH 500
#define PD_HEIGHT 492
#define PD_MARGIN 16
#define PD_ROW 24
#define PD_FIELD_H 22
#define PD_BUTTON_W 104
#define PD_BUTTON_H 28

static const wchar_t* k_print_class = L"SpdfWinPrintDialog";

typedef struct print_dialog_state {
    spdf_win_print_printers printers;
    spdf_win_print_request* req;
    DEVMODEW* devmode; /* the reader's, from Properties; moved into req on Print */
    int page_count;
    int current_page;
    int dark;
    int accepted;
    int finished;
    HBRUSH bg;
    HBRUSH field;
    HFONT font;
} print_dialog_state;

static COLORREF theme_ref(SpdfWinChromeColor c) {
    return RGB((int)(c.r * 255.0f + 0.5f), (int)(c.g * 255.0f + 0.5f), (int)(c.b * 255.0f + 0.5f));
}

/* --- reading the controls back -------------------------------------------- */

static int print_dialog_checked(HWND hwnd, int first, int last) {
    int id;
    for (id = first; id <= last; ++id)
        if (IsDlgButtonChecked(hwnd, id) == BST_CHECKED) return id - first;
    return 0;
}

static int print_dialog_number(HWND hwnd, int id, int fallback) {
    BOOL ok = FALSE;
    UINT value = GetDlgItemInt(hwnd, id, &ok, FALSE);
    return ok ? (int)value : fallback;
}

/* Everything the reader left, into the caller's request. The percentage goes
 * through spdf_win_print_choice_from_page() -- the same clamping the Scaling tab
 * in Windows' own dialog uses, so an empty field or 900% means the same thing
 * whichever dialog was shown. */
static void print_dialog_read(HWND hwnd, print_dialog_state* st) {
    wchar_t text[32];
    int at = (int)SendDlgItemMessageW(hwnd, PD_ID_PRINTER, CB_GETCURSEL, 0, 0);

    if (at >= 0 && at < st->printers.count)
        wcsncpy_s(st->req->printer, SPDF_WIN_PRINT_NAME_MAX, st->printers.name[at], _TRUNCATE);
    st->req->range = (spdf_win_print_range_mode)print_dialog_checked(hwnd, PD_ID_RANGE_ALL, PD_ID_RANGE_FROMTO);
    st->req->from = print_dialog_number(hwnd, PD_ID_FROM, 1);
    st->req->to = print_dialog_number(hwnd, PD_ID_TO, st->page_count);
    st->req->copies = print_dialog_number(hwnd, PD_ID_COPIES, 1);
    if (st->req->copies < 1) st->req->copies = 1;
    GetDlgItemTextW(hwnd, PD_ID_PERCENT, text, (int)(sizeof(text) / sizeof(text[0])));
    spdf_win_print_choice_from_page(print_dialog_checked(hwnd, PD_ID_SCALE_FIT, PD_ID_SCALE_CUSTOM), text,
                                    &st->req->choice);
    /* The DEVMODE moves; the state must not free what the request now owns. */
    free(st->req->devmode);
    st->req->devmode = st->devmode;
    st->devmode = NULL;
}

/* A field is only enabled while the radio that gives it meaning is checked --
 * a page range nobody asked for should not look editable. */
static void print_dialog_sync_enables(HWND hwnd) {
    int range = print_dialog_checked(hwnd, PD_ID_RANGE_ALL, PD_ID_RANGE_FROMTO);
    int scale = print_dialog_checked(hwnd, PD_ID_SCALE_FIT, PD_ID_SCALE_CUSTOM);
    EnableWindow(GetDlgItem(hwnd, PD_ID_FROM), range == SPDF_WIN_PRINT_RANGE_FROM_TO);
    EnableWindow(GetDlgItem(hwnd, PD_ID_TO), range == SPDF_WIN_PRINT_RANGE_FROM_TO);
    EnableWindow(GetDlgItem(hwnd, PD_ID_PERCENT), scale == SPDF_WIN_PRINT_SCALING_CUSTOM);
}

/* --- the window ----------------------------------------------------------- */

static LRESULT CALLBACK print_dialog_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
    print_dialog_state* st = (print_dialog_state*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);

    switch (msg) {
        case WM_ERASEBKGND:
            if (st) {
                RECT client;
                GetClientRect(hwnd, &client);
                FillRect((HDC)wparam, &client, st->bg);
                return 1;
            }
            break;
        case WM_CTLCOLORSTATIC:
        case WM_CTLCOLORBTN: {
            SpdfWinChromeTheme t = spdf_win_chrome_theme_for(st ? st->dark : 0);
            /* The note is an explanation, not a label, so it takes the quieter
             * of the two text colours -- the same distinction the About box
             * makes between its title and its version lines. */
            int is_note = GetDlgCtrlID((HWND)lparam) == PD_ID_NOTE;
            SetBkMode((HDC)wparam, TRANSPARENT);
            SetTextColor((HDC)wparam, theme_ref(is_note ? t.label_secondary : t.label));
            return (LRESULT)(st ? st->bg : (HBRUSH)(COLOR_BTNFACE + 1));
        }
        case WM_CTLCOLOREDIT:
        case WM_CTLCOLORLISTBOX: {
            SpdfWinChromeTheme t = spdf_win_chrome_theme_for(st ? st->dark : 0);
            SetBkColor((HDC)wparam, theme_ref(t.field_fill));
            SetTextColor((HDC)wparam, theme_ref(t.label));
            return (LRESULT)(st ? st->field : (HBRUSH)GetStockObject(WHITE_BRUSH));
        }
        case WM_COMMAND:
            switch (LOWORD(wparam)) {
                case PD_ID_RANGE_ALL:
                case PD_ID_RANGE_CURRENT:
                case PD_ID_RANGE_FROMTO:
                case PD_ID_SCALE_FIT:
                case PD_ID_SCALE_ACTUAL:
                case PD_ID_SCALE_CUSTOM:
                    if (HIWORD(wparam) == BN_CLICKED) print_dialog_sync_enables(hwnd);
                    return 0;
                case PD_ID_PRINTER:
                    /* A DEVMODE belongs to ONE driver. Carrying the paper size
                     * the reader chose for printer A over to printer B is how a
                     * job comes out on the wrong stock, so the choice is
                     * dropped with the printer. */
                    if (HIWORD(wparam) == CBN_SELCHANGE && st) {
                        free(st->devmode);
                        st->devmode = NULL;
                    }
                    return 0;
                case PD_ID_PROPS:
                    if (st) {
                        int at = (int)SendDlgItemMessageW(hwnd, PD_ID_PRINTER, CB_GETCURSEL, 0, 0);
                        if (at >= 0 && at < st->printers.count)
                            spdf_win_print_dialog_properties(hwnd, st->printers.name[at], &st->devmode);
                    }
                    return 0;
                case PD_ID_PRINT:
                    if (st && st->printers.count > 0) {
                        print_dialog_read(hwnd, st);
                        st->accepted = 1;
                        DestroyWindow(hwnd);
                    }
                    return 0;
                case PD_ID_CANCEL:
                case IDCANCEL: DestroyWindow(hwnd); return 0;
                default: break;
            }
            break;
        case WM_CLOSE: DestroyWindow(hwnd); return 0;
        case WM_DESTROY:
            if (st) st->finished = 1;
            /* WAKE THE MODAL LOOP: a close that arrives as a SENT message -- a
             * test's cross-thread SendMessageW(WM_CLOSE) -- is handled inside
             * GetMessageW, which then goes on waiting for a POSTED message that
             * never comes. See spdf_win_about.cpp, which explains why this is a
             * thread WM_NULL and not PostQuitMessage. */
            PostThreadMessageW(GetCurrentThreadId(), WM_NULL, 0, 0);
            return 0;
        default: break;
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static int print_dialog_register(void) {
    static int registered = 0;
    WNDCLASSEXW cls;
    if (registered) return 1;
    memset(&cls, 0, sizeof(cls));
    cls.cbSize = sizeof(cls);
    cls.lpfnWndProc = print_dialog_proc;
    cls.hInstance = GetModuleHandleW(NULL);
    /* MAKEINTRESOURCEW, not IDC_ARROW: this unit is built without UNICODE
     * defined, so the bare constant would expand to the ANSI form. See
     * spdf_win_properties_dialog.cpp. */
    cls.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
    cls.lpszClassName = k_print_class;
    if (!RegisterClassExW(&cls) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return 0;
    registered = 1;
    return 1;
}

/* THIS WINDOW'S DPI, and the constants below are all at 96. The app's manifest
 * declares PerMonitorV2, so CreateWindowExW's sizes are DEVICE pixels: on the
 * 150% display this was written on, a dialog laid out in raw constants comes
 * out two thirds the size it should be, with 15 px text in it. The port's other
 * dialogs (spdf_win_about.cpp, spdf_win_properties_dialog.cpp) have that
 * problem and get away with it because they are a paragraph and two buttons;
 * this one is three groups, a combo, six radios and three fields, and cramping
 * it by a third is the difference between readable and not. So every coordinate
 * and the font go through S() below.
 *
 * GetDpiForWindow is Windows 10 1607+, which is what the manifest's
 * supportedOS list already promises; resolved dynamically anyway, because a
 * missing export must be a plain 96 and not a crash. */
static int print_dialog_dpi(HWND hwnd) {
    typedef UINT(WINAPI * dpi_for_window_fn)(HWND);
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    dpi_for_window_fn fn = user32 ? (dpi_for_window_fn)GetProcAddress(user32, "GetDpiForWindow") : NULL;
    UINT dpi = fn ? fn(hwnd) : 0;
    return dpi >= 96 && dpi <= 480 ? (int)dpi : 96;
}

#define S(v) MulDiv((v), dpi, 96)

/* One control, with the shell font and -- in dark mode only -- no visual style.
 * Every control goes through here so neither can be forgotten on one of them. */
static HWND print_dialog_add(HWND parent, print_dialog_state* st, const wchar_t* cls, const wchar_t* text, DWORD style,
                             DWORD ex_style, int x, int y, int w, int h, int id) {
    HWND child = CreateWindowExW(ex_style, cls, text, style | WS_CHILD | WS_VISIBLE, x, y, w, h, parent,
                                 (HMENU)(INT_PTR)id, GetModuleHandleW(NULL), NULL);
    if (!child) return NULL;
    SendMessageW(child, WM_SETFONT, (WPARAM)st->font, TRUE);
    if (st->dark) SetWindowTheme(child, L"", L"");
    return child;
}

int spdf_win_print_dialog_show(HWND parent, int dark, const wchar_t* doc_name, int page_count, int current_page,
                               const char* note, spdf_win_print_request* req, char* err, size_t err_len) {
    print_dialog_state st;
    SpdfWinChromeTheme t = spdf_win_chrome_theme_for(dark);
    wchar_t label[160];
    wchar_t wnote[400];
    HWND hwnd, combo, focus;
    RECT client;
    MSG msg;
    BOOL parent_was_enabled = FALSE;
    int i, at, W, y, group_w, right, dpi;

    if (err && err_len) err[0] = '\0';
    if (!req || page_count <= 0) return 0;
    if (!print_dialog_register()) return 0;

    memset(&st, 0, sizeof(st));
    st.req = req;
    st.page_count = page_count;
    st.current_page = current_page;
    st.dark = dark;
    spdf_win_print_dialog_printers(&st.printers);
    if (st.printers.count <= 0) {
        if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "No printers are installed on this computer.");
        return 0;
    }
    /* The remembered printer if it is still there, the default otherwise. */
    at = spdf_win_print_printers_index_of(&st.printers, req->printer);
    if (at < 0) at = st.printers.selected >= 0 ? st.printers.selected : 0;

    st.bg = CreateSolidBrush(theme_ref(t.band));
    st.field = CreateSolidBrush(theme_ref(t.field_fill));

    _snwprintf_s(label, _TRUNCATE, L"Print%s%s", doc_name && *doc_name ? L" — " : L"",
                 doc_name && *doc_name ? doc_name : L"");
    /* Created at the 96-dpi size and then resized to the DPI it landed on: the
     * window has to exist before GetDpiForWindow can be asked about it. */
    hwnd = CreateWindowExW(WS_EX_DLGMODALFRAME | WS_EX_CONTROLPARENT, k_print_class, label,
                           WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, PD_WIDTH, PD_HEIGHT,
                           parent, NULL, GetModuleHandleW(NULL), NULL);
    if (!hwnd) {
        if (err && err_len)
            _snprintf_s(err, err_len, _TRUNCATE, "The print dialog window could not be created (error %lu).",
                        (unsigned long)GetLastError());
        DeleteObject(st.bg);
        DeleteObject(st.field);
        return 0;
    }
    dpi = print_dialog_dpi(hwnd);
    st.font = CreateFontW(-S(15), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                          CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    if (dpi != 96)
        SetWindowPos(hwnd, NULL, 0, 0, S(PD_WIDTH), S(PD_HEIGHT), SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)&st);
    spdf_win_about_dark_caption(hwnd, dark);
    GetClientRect(hwnd, &client);
    W = client.right - client.left;
    group_w = W - S(PD_MARGIN) * 2;
    right = W - S(PD_MARGIN);

    /* --- the printer, and the driver's own settings --- */
    y = S(PD_MARGIN);
    print_dialog_add(hwnd, &st, L"STATIC", L"Printer:", SS_LEFT, 0, S(PD_MARGIN), y + S(3), S(56), S(18), 0);
    combo = print_dialog_add(hwnd, &st, L"COMBOBOX", NULL, CBS_DROPDOWNLIST | WS_VSCROLL | WS_TABSTOP, 0,
                             S(PD_MARGIN + 60), y, right - S(PD_BUTTON_W + 8 + PD_MARGIN + 60), S(240),
                             PD_ID_PRINTER);
    print_dialog_add(hwnd, &st, L"BUTTON", L"P&roperties...", BS_PUSHBUTTON | WS_TABSTOP, 0, right - S(PD_BUTTON_W),
                     y - S(1), S(PD_BUTTON_W), S(PD_FIELD_H + 2), PD_ID_PROPS);
    for (i = 0; i < st.printers.count; ++i)
        SendMessageW(combo, CB_ADDSTRING, 0, (LPARAM)st.printers.name[i]);
    SendMessageW(combo, CB_SETCURSEL, (WPARAM)at, 0);

    /* --- the pages --- */
    y += S(40);
    print_dialog_add(hwnd, &st, L"BUTTON", L"Pages", BS_GROUPBOX, 0, S(PD_MARGIN), y, group_w, S(112), 0);
    _snwprintf_s(label, _TRUNCATE, L"&All %d pages", page_count);
    print_dialog_add(hwnd, &st, L"BUTTON", label, BS_AUTORADIOBUTTON | WS_GROUP | WS_TABSTOP, 0, S(PD_MARGIN + 12),
                     y + S(22), group_w - S(24), S(20), PD_ID_RANGE_ALL);
    if (current_page >= 0) _snwprintf_s(label, _TRUNCATE, L"C&urrent page (%d)", current_page + 1);
    else _snwprintf_s(label, _TRUNCATE, L"C&urrent page");
    print_dialog_add(hwnd, &st, L"BUTTON", label, BS_AUTORADIOBUTTON, 0, S(PD_MARGIN + 12), y + S(46),
                     group_w - S(24), S(20), PD_ID_RANGE_CURRENT);
    /* Greyed rather than guessing: a caller that does not know the page would
     * silently print page 1 (spdf_win_print_dialog_range), and a reader must
     * never be the one making that substitution. */
    if (current_page < 0) EnableWindow(GetDlgItem(hwnd, PD_ID_RANGE_CURRENT), FALSE);
    print_dialog_add(hwnd, &st, L"BUTTON", L"Pa&ges", BS_AUTORADIOBUTTON, 0, S(PD_MARGIN + 12), y + S(70), S(64),
                     S(20), PD_ID_RANGE_FROMTO);
    print_dialog_add(hwnd, &st, L"EDIT", L"", ES_NUMBER | ES_AUTOHSCROLL | WS_TABSTOP, WS_EX_CLIENTEDGE,
                     S(PD_MARGIN + 82), y + S(68), S(52), S(PD_FIELD_H), PD_ID_FROM);
    print_dialog_add(hwnd, &st, L"STATIC", L"to", SS_CENTER, 0, S(PD_MARGIN + 138), y + S(72), S(20), S(18), 0);
    print_dialog_add(hwnd, &st, L"EDIT", L"", ES_NUMBER | ES_AUTOHSCROLL | WS_TABSTOP, WS_EX_CLIENTEDGE,
                     S(PD_MARGIN + 162), y + S(68), S(52), S(PD_FIELD_H), PD_ID_TO);
    SetDlgItemInt(hwnd, PD_ID_FROM, (UINT)(current_page >= 0 ? current_page + 1 : 1), FALSE);
    SetDlgItemInt(hwnd, PD_ID_TO, (UINT)page_count, FALSE);
    CheckRadioButton(hwnd, PD_ID_RANGE_ALL, PD_ID_RANGE_FROMTO, PD_ID_RANGE_ALL);

    /* --- the scale, the app's own, in the macOS accessory's words --- */
    y += S(126);
    print_dialog_add(hwnd, &st, L"BUTTON", L"Scaling", BS_GROUPBOX, 0, S(PD_MARGIN), y, group_w, S(112), 0);
    print_dialog_add(hwnd, &st, L"BUTTON", L"&Fit to the printable area", BS_AUTORADIOBUTTON | WS_GROUP | WS_TABSTOP,
                     0, S(PD_MARGIN + 12), y + S(22), group_w - S(24), S(20), PD_ID_SCALE_FIT);
    print_dialog_add(hwnd, &st, L"BUTTON", L"Act&ual size (100%)", BS_AUTORADIOBUTTON, 0, S(PD_MARGIN + 12),
                     y + S(46), group_w - S(24), S(20), PD_ID_SCALE_ACTUAL);
    print_dialog_add(hwnd, &st, L"BUTTON", L"&Custom:", BS_AUTORADIOBUTTON, 0, S(PD_MARGIN + 12), y + S(70), S(76),
                     S(20), PD_ID_SCALE_CUSTOM);
    print_dialog_add(hwnd, &st, L"EDIT", L"", ES_NUMBER | ES_AUTOHSCROLL | WS_TABSTOP, WS_EX_CLIENTEDGE,
                     S(PD_MARGIN + 94), y + S(68), S(52), S(PD_FIELD_H), PD_ID_PERCENT);
    print_dialog_add(hwnd, &st, L"STATIC", L"%  (10 to 800)", SS_LEFT, 0, S(PD_MARGIN + 152), y + S(72), S(140),
                     S(18), 0);
    spdf_win_print_percent_text(req->choice.custom_scale, label, 16);
    SetDlgItemTextW(hwnd, PD_ID_PERCENT, label);
    CheckRadioButton(hwnd, PD_ID_SCALE_FIT, PD_ID_SCALE_CUSTOM,
                     PD_ID_SCALE_FIT + (req->choice.mode == SPDF_WIN_PRINT_SCALING_ACTUAL   ? 1
                                        : req->choice.mode == SPDF_WIN_PRINT_SCALING_CUSTOM ? 2
                                                                                            : 0));

    /* --- copies --- */
    y += S(126);
    print_dialog_add(hwnd, &st, L"STATIC", L"Cop&ies:", SS_LEFT, 0, S(PD_MARGIN), y + S(3), S(56), S(18), 0);
    print_dialog_add(hwnd, &st, L"EDIT", L"", ES_NUMBER | ES_AUTOHSCROLL | WS_TABSTOP, WS_EX_CLIENTEDGE,
                     S(PD_MARGIN + 60), y, S(52), S(PD_FIELD_H), PD_ID_COPIES);
    SetDlgItemInt(hwnd, PD_ID_COPIES, (UINT)(req->copies > 0 ? req->copies : 1), FALSE);

    /* --- why the reader is looking at this and not at Windows' dialog --- */
    if (note && *note && MultiByteToWideChar(CP_UTF8, 0, note, -1, wnote, (int)(sizeof(wnote) / sizeof(wnote[0]))) > 0)
        /* 52, not 36: the sentence wraps to two lines at every width this
         * dialog has, and a static clips rather than growing -- measured at 144
         * dpi, where 36 cut the descenders off the second line. */
        print_dialog_add(hwnd, &st, L"STATIC", wnote, SS_LEFT, 0, S(PD_MARGIN), y + S(32), group_w, S(52),
                         PD_ID_NOTE);

    print_dialog_add(hwnd, &st, L"BUTTON", L"&Print", BS_PUSHBUTTON | WS_TABSTOP, 0, right - S(PD_BUTTON_W * 2 + 8),
                     client.bottom - S(PD_MARGIN + PD_BUTTON_H), S(PD_BUTTON_W), S(PD_BUTTON_H), PD_ID_PRINT);
    print_dialog_add(hwnd, &st, L"BUTTON", L"Cancel", BS_PUSHBUTTON | WS_TABSTOP, 0, right - S(PD_BUTTON_W),
                     client.bottom - S(PD_MARGIN + PD_BUTTON_H), S(PD_BUTTON_W), S(PD_BUTTON_H), PD_ID_CANCEL);

    print_dialog_sync_enables(hwnd);
    if (parent) parent_was_enabled = IsWindowEnabled(parent);
    if (parent && parent_was_enabled) EnableWindow(parent, FALSE);
    ShowWindow(hwnd, SW_SHOW);
    focus = GetDlgItem(hwnd, PD_ID_PRINTER);
    if (focus) SetFocus(focus);

    while (!st.finished && GetMessageW(&msg, NULL, 0, 0) > 0) {
        if (msg.message == WM_KEYDOWN && msg.wParam == VK_ESCAPE) {
            DestroyWindow(hwnd);
            continue;
        }
        if (msg.message == WM_KEYDOWN && msg.wParam == VK_RETURN) {
            SendMessageW(hwnd, WM_COMMAND, MAKEWPARAM(PD_ID_PRINT, BN_CLICKED), (LPARAM)GetDlgItem(hwnd, PD_ID_PRINT));
            continue;
        }
        /* Tab, the arrow keys within a radio group, and the &mnemonics. */
        if (IsDialogMessageW(hwnd, &msg)) continue;
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    if (parent && parent_was_enabled) {
        EnableWindow(parent, TRUE);
        SetForegroundWindow(parent);
    }
    free(st.devmode); /* NULL once Print has moved it into the request */
    DeleteObject(st.bg);
    DeleteObject(st.field);
    DeleteObject(st.font);
    return st.accepted;
}

#undef S
