/* spdf_win_menu.h — every command the Windows shell can be asked to run, as
 * data: one table of (command, menu, title, accelerator).
 *
 * WHAT THIS IS. The Win32 answer to portable/linux/gtk4/spdf_shortcuts.c, which
 * is "the single registry of every GAction name in the GTK4 shell, with
 * accelerators (Mac map, Cmd -> Ctrl) and the F1 cheat sheet, which is a
 * GtkShortcutsWindow generated from the same table so the two can never drift
 * apart". Same discipline, same reason: the menu bar, the keyboard and (later) a
 * command palette must offer exactly one set of commands, and the only way that
 * survives edits is for all three to read one table.
 *
 * WHY THE TABLE IS PURE AND HEADER-ONLY, when the thing it builds is an HMENU.
 * spdf_win_chrome.h's second rule -- "hit-testing and painting agree only if
 * they call the same functions" -- has a keyboard analogue: the accelerator
 * PRINTED next to a menu item and the accelerator that actually FIRES agree only
 * if they come from the same row. So the row carries both, and matching a
 * keystroke to a command is a pure function a plain C test can drive with no
 * window, no menu and no message pump (portable/win/tests/menu_test.c). Only the
 * HMENU construction, the popup menus and the file dialog need Win32, and those
 * live in spdf_win_menu.cpp.
 *
 * THE GROUPING AND THE TITLES ARE macOS'S, transcribed from
 * portable/mac/ShenzhenPDFMac.mm:2133-2424 -- File, Go To, Zoom, View, Edit, in
 * that order and with those item titles -- minus the commands this port does not
 * have yet. Nothing here is invented: an item exists only if the command behind
 * it exists.
 *
 * THE ACCELERATORS ARE Cmd -> Ctrl, which is the mapping the GTK4 frontend
 * already made once (spdf_shortcuts.c:2). Where macOS uses Option (its page
 * navigation: Option+arrows) the Windows spelling is Alt, which is the same
 * physical key in the same role. Three deliberate departures from a literal
 * transcription, each one following GTK4's existing choice rather than inventing
 * a third answer:
 *
 *   - 100% is Ctrl+0, not Ctrl+4 (macOS's Cmd+4). GTK4: win.zoom-actual.
 *   - Previous/Next Tab are Ctrl+PageUp / Ctrl+PageDown, not Ctrl+Left/Right,
 *     which on Windows are word-motion keys. GTK4: win.prev-tab / win.next-tab.
 *     Ctrl+Tab and Ctrl+Shift+Tab keep working as they already did.
 *   - Toggle Side Panel is F9. GTK4: win.sidebar. macOS binds no key.
 *
 * ONE BEHAVIOUR CHANGE THIS TABLE MAKES ON PURPOSE. The Windows keymap had
 * Ctrl+1 = Fit Width and Ctrl+2 = Fit Page, which is neither macOS's order
 * (Cmd+1 Fit Page, Cmd+2 Fit Width, Cmd+3 Fit Height) nor GTK4's (identical to
 * macOS). It is now macOS's, because a menu that PRINTS an accelerator makes the
 * disagreement visible and a reader who uses two of the three frontends would
 * hit it immediately.
 */
#ifndef SPDF_WIN_MENU_H
#define SPDF_WIN_MENU_H

#include <stddef.h> /* NULL, and nothing else -- this header takes no Win32 */
#include <wchar.h>

#if defined(_MSC_VER) && !defined(__cplusplus)
#define SPDF_WIN_MENU_INLINE __inline
#else
#define SPDF_WIN_MENU_INLINE inline
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* --- keys ----------------------------------------------------------------
 *
 * The numeric VK_* values, spelled out rather than taken from <windows.h>, so
 * this header stays free of Win32 exactly as spdf_win_chrome.h and
 * spdf_win_tabstrip.h are. They are ABI: WM_KEYDOWN's wParam is these numbers,
 * and they have not changed since Win16. Letter and digit keys are their ASCII
 * uppercase code, which is also what WM_KEYDOWN reports. */
#define SPDF_WIN_KEY_BACK 0x08   /* VK_BACK */
#define SPDF_WIN_KEY_TAB 0x09    /* VK_TAB */
#define SPDF_WIN_KEY_RETURN 0x0D /* VK_RETURN */
#define SPDF_WIN_KEY_ESCAPE 0x1B /* VK_ESCAPE */
#define SPDF_WIN_KEY_PRIOR 0x21  /* VK_PRIOR, Page Up */
#define SPDF_WIN_KEY_NEXT 0x22   /* VK_NEXT, Page Down */
#define SPDF_WIN_KEY_END 0x23    /* VK_END */
#define SPDF_WIN_KEY_HOME 0x24   /* VK_HOME */
#define SPDF_WIN_KEY_LEFT 0x25   /* VK_LEFT */
#define SPDF_WIN_KEY_UP 0x26     /* VK_UP */
#define SPDF_WIN_KEY_RIGHT 0x27  /* VK_RIGHT */
#define SPDF_WIN_KEY_DOWN 0x28   /* VK_DOWN */
#define SPDF_WIN_KEY_DELETE 0x2E /* VK_DELETE */
#define SPDF_WIN_KEY_ADD 0x6B    /* VK_ADD, numeric keypad */
#define SPDF_WIN_KEY_SUBTRACT 0x6D /* VK_SUBTRACT */
#define SPDF_WIN_KEY_F9 0x78     /* VK_F9 */
#define SPDF_WIN_KEY_OEM_PLUS 0xBB  /* VK_OEM_PLUS, the '=' key on a US layout */
#define SPDF_WIN_KEY_OEM_MINUS 0xBD /* VK_OEM_MINUS */

/* The modifier bits, matching spdf_win_window.h's SPDF_WIN_MOD_* exactly so a
 * spdf_win_input's `mods` can be handed to spdf_win_menu_command_for_key()
 * unconverted. Two spellings of the same three bits would be one conversion
 * function away from a Shift that silently means Ctrl. */
#define SPDF_WIN_ACCEL_CTRL 0x1u
#define SPDF_WIN_ACCEL_SHIFT 0x2u
#define SPDF_WIN_ACCEL_ALT 0x4u

/* --- commands ------------------------------------------------------------
 *
 * The value IS the WM_COMMAND id, offset by SPDF_WIN_MENU_ID_BASE. Renumbering
 * is free (nothing persists these), but the ORDER is the menu's visual order,
 * which is the same convention spdf_win_chrome_toolbar.h states for its items. */
typedef enum spdf_win_command {
    SPDF_WIN_CMD_NONE = 0,

    /* File (:2155-2197) */
    SPDF_WIN_CMD_OPEN,      /* "Open..."  */
    SPDF_WIN_CMD_NEW_TAB,   /* GTK4 win.new-tab; the strip's `+` and Ctrl+T */
    SPDF_WIN_CMD_CLOSE_TAB, /* "Close"    */
    SPDF_WIN_CMD_QUIT,      /* "Quit Shenzhen PDF" */

    /* Go To (:2200-2245) */
    SPDF_WIN_CMD_FIRST_PAGE,
    SPDF_WIN_CMD_PREV_PAGE,
    SPDF_WIN_CMD_NEXT_PAGE,
    SPDF_WIN_CMD_LAST_PAGE,
    SPDF_WIN_CMD_GOTO_PAGE, /* "Go To Page..." -- focuses the page field */
    SPDF_WIN_CMD_PREV_TAB,
    SPDF_WIN_CMD_NEXT_TAB,

    /* Zoom (:2247-2261) */
    SPDF_WIN_CMD_ZOOM_IN,
    SPDF_WIN_CMD_ZOOM_OUT,
    SPDF_WIN_CMD_ZOOM_ACTUAL,
    SPDF_WIN_CMD_FIT_PAGE,
    SPDF_WIN_CMD_FIT_WIDTH,
    SPDF_WIN_CMD_FIT_HEIGHT,

    /* View (:2263-2318) */
    SPDF_WIN_CMD_TOGGLE_SIDEBAR,
    SPDF_WIN_CMD_TOGGLE_MINIMAP,
    SPDF_WIN_CMD_TOGGLE_THEME,

    /* Edit (:2342-2365) */
    SPDF_WIN_CMD_COPY, /* "Copy Selected Document Text"; GTK4 win.copy */
    SPDF_WIN_CMD_FIND,
    SPDF_WIN_CMD_FIND_NEXT,
    SPDF_WIN_CMD_FIND_PREV,
    SPDF_WIN_CMD_FIND_REGEX,

    SPDF_WIN_CMD_COUNT
} spdf_win_command;

/* Which top-level menu an item belongs to. NONE is an ACCELERATOR-ONLY row: a
 * second key for a command that already has a menu item (Ctrl+= as well as
 * Ctrl++), which must fire but must not appear twice in the menu. */
typedef enum spdf_win_menu_id {
    SPDF_WIN_MENU_NONE = 0,
    SPDF_WIN_MENU_FILE,
    SPDF_WIN_MENU_GO,
    SPDF_WIN_MENU_ZOOM,
    SPDF_WIN_MENU_VIEW,
    SPDF_WIN_MENU_EDIT,
    SPDF_WIN_MENU_COUNT
} spdf_win_menu_id;

/* WM_COMMAND ids start here. Above every standard control id and far below the
 * 0xF000 range Windows reserves for system commands (SC_*). */
#define SPDF_WIN_MENU_ID_BASE 0x400

/* The tab overflow popup's ids: base + tab index. A separate range so a stray
 * WM_COMMAND can never be read as both a tab and a command. */
#define SPDF_WIN_MENU_TAB_ID_BASE 0x800
#define SPDF_WIN_MENU_TAB_ID_MAX 0x8ff

typedef struct SpdfWinMenuItem {
    int command;       /* spdf_win_command; SPDF_WIN_CMD_NONE marks a separator */
    int menu;          /* spdf_win_menu_id; NONE means accelerator-only */
    const wchar_t* title;  /* with the & mnemonic Win32 wants; NULL for a separator */
    const wchar_t* accel;  /* what the menu PRINTS, or NULL */
    unsigned key;      /* 0 when the item has no accelerator */
    unsigned mods;
    /* Drawn with a check mark, and CheckMenuItem'd from SpdfWinMenuState below.
     * macOS does the same three through -validateMenuItem: (:2266-2280). */
    int checkable;
} SpdfWinMenuItem;

/* The table. Order is menu order; a separator is a row whose command is NONE.
 *
 * `static` in a header gives each translation unit its own copy, which is what
 * the rest of this port's pure headers already do (spdf_win_chrome.h's inline
 * functions) and costs a few hundred bytes in the two files that include it. */
static const SpdfWinMenuItem k_spdf_win_menu[] = {
    /* --- File --------------------------------------------------------- */
    {SPDF_WIN_CMD_OPEN, SPDF_WIN_MENU_FILE, L"&Open...", L"Ctrl+O", 'O', SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_NEW_TAB, SPDF_WIN_MENU_FILE, L"Open in New &Tab...", L"Ctrl+T", 'T', SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_NONE, SPDF_WIN_MENU_FILE, NULL, NULL, 0, 0, 0},
    {SPDF_WIN_CMD_CLOSE_TAB, SPDF_WIN_MENU_FILE, L"&Close", L"Ctrl+W", 'W', SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_NONE, SPDF_WIN_MENU_FILE, NULL, NULL, 0, 0, 0},
    {SPDF_WIN_CMD_QUIT, SPDF_WIN_MENU_FILE, L"&Quit Shenzhen PDF", L"Ctrl+Q", 'Q', SPDF_WIN_ACCEL_CTRL, 0},

    /* --- Go To -------------------------------------------------------- */
    {SPDF_WIN_CMD_FIRST_PAGE, SPDF_WIN_MENU_GO, L"&First Page", L"Alt+Up", SPDF_WIN_KEY_UP, SPDF_WIN_ACCEL_ALT, 0},
    {SPDF_WIN_CMD_PREV_PAGE, SPDF_WIN_MENU_GO, L"&Previous Page", L"Alt+Left", SPDF_WIN_KEY_LEFT, SPDF_WIN_ACCEL_ALT,
     0},
    {SPDF_WIN_CMD_NEXT_PAGE, SPDF_WIN_MENU_GO, L"&Next Page", L"Alt+Right", SPDF_WIN_KEY_RIGHT, SPDF_WIN_ACCEL_ALT, 0},
    {SPDF_WIN_CMD_LAST_PAGE, SPDF_WIN_MENU_GO, L"&Last Page", L"Alt+Down", SPDF_WIN_KEY_DOWN, SPDF_WIN_ACCEL_ALT, 0},
    {SPDF_WIN_CMD_NONE, SPDF_WIN_MENU_GO, NULL, NULL, 0, 0, 0},
    {SPDF_WIN_CMD_GOTO_PAGE, SPDF_WIN_MENU_GO, L"&Go To Page...", L"Ctrl+L", 'L', SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_NONE, SPDF_WIN_MENU_GO, NULL, NULL, 0, 0, 0},
    {SPDF_WIN_CMD_PREV_TAB, SPDF_WIN_MENU_GO, L"Previous &Tab", L"Ctrl+PgUp", SPDF_WIN_KEY_PRIOR,
     SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_NEXT_TAB, SPDF_WIN_MENU_GO, L"Next Ta&b", L"Ctrl+PgDn", SPDF_WIN_KEY_NEXT, SPDF_WIN_ACCEL_CTRL, 0},

    /* --- Zoom --------------------------------------------------------- */
    {SPDF_WIN_CMD_ZOOM_IN, SPDF_WIN_MENU_ZOOM, L"Zoom &In", L"Ctrl++", SPDF_WIN_KEY_OEM_PLUS, SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_ZOOM_OUT, SPDF_WIN_MENU_ZOOM, L"Zoom &Out", L"Ctrl+-", SPDF_WIN_KEY_OEM_MINUS, SPDF_WIN_ACCEL_CTRL,
     0},
    {SPDF_WIN_CMD_ZOOM_ACTUAL, SPDF_WIN_MENU_ZOOM, L"&100%", L"Ctrl+0", '0', SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_NONE, SPDF_WIN_MENU_ZOOM, NULL, NULL, 0, 0, 0},
    {SPDF_WIN_CMD_FIT_PAGE, SPDF_WIN_MENU_ZOOM, L"Fit &Page", L"Ctrl+1", '1', SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_FIT_WIDTH, SPDF_WIN_MENU_ZOOM, L"Fit &Width", L"Ctrl+2", '2', SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_FIT_HEIGHT, SPDF_WIN_MENU_ZOOM, L"Fit &Height", L"Ctrl+3", '3', SPDF_WIN_ACCEL_CTRL, 0},

    /* --- View --------------------------------------------------------- */
    {SPDF_WIN_CMD_TOGGLE_SIDEBAR, SPDF_WIN_MENU_VIEW, L"Show &Side Panel", L"F9", SPDF_WIN_KEY_F9, 0, 1},
    {SPDF_WIN_CMD_TOGGLE_MINIMAP, SPDF_WIN_MENU_VIEW, L"Show &Minimap", NULL, 0, 0, 1},
    {SPDF_WIN_CMD_TOGGLE_THEME, SPDF_WIN_MENU_VIEW, L"&Dark Reading Theme", L"Ctrl+Shift+I", 'I',
     SPDF_WIN_ACCEL_CTRL | SPDF_WIN_ACCEL_SHIFT, 1},

    /* --- Edit --------------------------------------------------------- */
    /* macOS has a plain "Copy" on Cmd+C for its own text fields and a separate
     * "Copy Selected Document Text" with no key (:2346, :2350). There is one
     * selection to copy on Windows -- the document's -- so the two are one item,
     * on Ctrl+C, which is also GTK4's win.copy. */
    {SPDF_WIN_CMD_COPY, SPDF_WIN_MENU_EDIT, L"&Copy", L"Ctrl+C", 'C', SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_NONE, SPDF_WIN_MENU_EDIT, NULL, NULL, 0, 0, 0},
    {SPDF_WIN_CMD_FIND, SPDF_WIN_MENU_EDIT, L"&Find", L"Ctrl+F", 'F', SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_FIND_NEXT, SPDF_WIN_MENU_EDIT, L"Find &Next", L"Ctrl+G", 'G', SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_FIND_PREV, SPDF_WIN_MENU_EDIT, L"Find &Previous", L"Ctrl+Shift+G", 'G',
     SPDF_WIN_ACCEL_CTRL | SPDF_WIN_ACCEL_SHIFT, 0},
    {SPDF_WIN_CMD_NONE, SPDF_WIN_MENU_EDIT, NULL, NULL, 0, 0, 0},
    {SPDF_WIN_CMD_FIND_REGEX, SPDF_WIN_MENU_EDIT, L"&Regex", NULL, 0, 0, 1},

    /* --- accelerator-only rows ----------------------------------------
     *
     * The keypad and the shifted-'=' spellings of zoom, which GTK4 also carries
     * as extra accels on the same actions (spdf_shortcuts.c win.zoom-in has
     * three). They fire but are not drawn: a menu that lists "Zoom In" twice
     * reads as a bug. */
    {SPDF_WIN_CMD_ZOOM_IN, SPDF_WIN_MENU_NONE, NULL, NULL, SPDF_WIN_KEY_ADD, SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_ZOOM_OUT, SPDF_WIN_MENU_NONE, NULL, NULL, SPDF_WIN_KEY_SUBTRACT, SPDF_WIN_ACCEL_CTRL, 0},
    /* Ctrl+Tab and Ctrl+Shift+Tab, which this port already had before there was
     * a menu and which readers coming from a browser reach for first. The menu
     * PRINTS Ctrl+PageUp / Ctrl+PageDown, following GTK4; both work. */
    {SPDF_WIN_CMD_NEXT_TAB, SPDF_WIN_MENU_NONE, NULL, NULL, SPDF_WIN_KEY_TAB, SPDF_WIN_ACCEL_CTRL, 0},
    {SPDF_WIN_CMD_PREV_TAB, SPDF_WIN_MENU_NONE, NULL, NULL, SPDF_WIN_KEY_TAB,
     SPDF_WIN_ACCEL_CTRL | SPDF_WIN_ACCEL_SHIFT, 0},
    /* Ctrl+Shift+= IS Ctrl++ on a US layout: the '+' glyph is the shifted '=',
     * and WM_KEYDOWN reports the unshifted VK either way. Without this row the
     * accelerator the menu PRINTS is the one that does not work. */
    {SPDF_WIN_CMD_ZOOM_IN, SPDF_WIN_MENU_NONE, NULL, NULL, SPDF_WIN_KEY_OEM_PLUS,
     SPDF_WIN_ACCEL_CTRL | SPDF_WIN_ACCEL_SHIFT, 0}
};

static SPDF_WIN_MENU_INLINE const SpdfWinMenuItem* spdf_win_menu_table(int* out_count) {
    if (out_count) *out_count = (int)(sizeof(k_spdf_win_menu) / sizeof(k_spdf_win_menu[0]));
    return k_spdf_win_menu;
}

/* The title of a top-level menu, with its mnemonic. macOS's own five, in
 * macOS's own order (:2155, :2200, :2247, :2263, :2342). */
static SPDF_WIN_MENU_INLINE const wchar_t* spdf_win_menu_title(int menu) {
    switch (menu) {
        case SPDF_WIN_MENU_FILE: return L"&File";
        case SPDF_WIN_MENU_GO: return L"&Go To";
        case SPDF_WIN_MENU_ZOOM: return L"&Zoom";
        case SPDF_WIN_MENU_VIEW: return L"&View";
        case SPDF_WIN_MENU_EDIT: return L"&Edit";
        default: return NULL;
    }
}

/* THE ONE ENTRY POINT FOR THE KEYBOARD.
 *
 * Returns the command a keystroke runs, or SPDF_WIN_CMD_NONE.
 *
 * `mods` MUST MATCH EXACTLY, and that is the point rather than an omission:
 * Ctrl+Shift+G is a different command from Ctrl+G, so a subset test would let
 * Find Previous fire Find Next -- and it must be the FIRST row that matches, so
 * that a more-modified row placed later can never be shadowed. Both are checked
 * in portable/win/tests/menu_test.c. */
static SPDF_WIN_MENU_INLINE int spdf_win_menu_command_for_key(unsigned key, unsigned mods) {
    int i, n = 0;
    const SpdfWinMenuItem* table = spdf_win_menu_table(&n);
    if (!key) return SPDF_WIN_CMD_NONE;
    /* Only the three bits this table speaks. A caller that also reports, say, a
     * Windows key must not thereby lose every accelerator. */
    mods &= (SPDF_WIN_ACCEL_CTRL | SPDF_WIN_ACCEL_SHIFT | SPDF_WIN_ACCEL_ALT);
    for (i = 0; i < n; ++i) {
        if (!table[i].key || table[i].command == SPDF_WIN_CMD_NONE) continue;
        if (table[i].key == key && table[i].mods == mods) return table[i].command;
    }
    return SPDF_WIN_CMD_NONE;
}

/* The row that DRAWS a command, for a caller that wants its title or its
 * printed accelerator (the command palette, and the menu builder). NULL for a
 * command with no menu row. */
static SPDF_WIN_MENU_INLINE const SpdfWinMenuItem* spdf_win_menu_item_for_command(int command) {
    int i, n = 0;
    const SpdfWinMenuItem* table = spdf_win_menu_table(&n);
    /* SPDF_WIN_CMD_NONE is the SEPARATOR marker, not a command: without this
     * guard the first separator answers for it, and a caller asking for the
     * title of "no command" gets a row with a NULL title. */
    if (command == SPDF_WIN_CMD_NONE) return NULL;
    for (i = 0; i < n; ++i)
        if (table[i].command == command && table[i].menu != SPDF_WIN_MENU_NONE) return &table[i];
    return NULL;
}

/* --- what the menu shows about the app ----------------------------------
 *
 * The three check marks and the one greyed item, gathered into a value so
 * spdf_win_menu_sync() takes no app pointer and a test can build one by hand --
 * the same reason SpdfWinChromeModel is a plain value type. */
typedef struct SpdfWinMenuState {
    int sidebar_visible;
    int minimap_visible;
    int dark_theme;
    int regex;
    int can_close_tab;
    int has_document;
} SpdfWinMenuState;

/* Whether an item should be enabled given that state. Pure, so the greying rule
 * is testable; spdf_win_menu_sync() applies it. */
static SPDF_WIN_MENU_INLINE int spdf_win_menu_command_enabled(int command, const SpdfWinMenuState* st) {
    if (!st) return 1;
    switch (command) {
        case SPDF_WIN_CMD_CLOSE_TAB: return st->can_close_tab != 0;
        /* Everything that needs a document to act on. Open, New Tab and Quit
         * deliberately stay live with no document -- they are the way out of
         * that state. */
        case SPDF_WIN_CMD_FIRST_PAGE:
        case SPDF_WIN_CMD_PREV_PAGE:
        case SPDF_WIN_CMD_NEXT_PAGE:
        case SPDF_WIN_CMD_LAST_PAGE:
        case SPDF_WIN_CMD_GOTO_PAGE:
        case SPDF_WIN_CMD_ZOOM_IN:
        case SPDF_WIN_CMD_ZOOM_OUT:
        case SPDF_WIN_CMD_ZOOM_ACTUAL:
        case SPDF_WIN_CMD_FIT_PAGE:
        case SPDF_WIN_CMD_FIT_WIDTH:
        case SPDF_WIN_CMD_FIT_HEIGHT:
        case SPDF_WIN_CMD_COPY:
        case SPDF_WIN_CMD_FIND:
        case SPDF_WIN_CMD_FIND_NEXT:
        case SPDF_WIN_CMD_FIND_PREV: return st->has_document != 0;
        default: return 1;
    }
}

/* Whether a checkable item is ticked. */
static SPDF_WIN_MENU_INLINE int spdf_win_menu_command_checked(int command, const SpdfWinMenuState* st) {
    if (!st) return 0;
    switch (command) {
        case SPDF_WIN_CMD_TOGGLE_SIDEBAR: return st->sidebar_visible != 0;
        case SPDF_WIN_CMD_TOGGLE_MINIMAP: return st->minimap_visible != 0;
        case SPDF_WIN_CMD_TOGGLE_THEME: return st->dark_theme != 0;
        case SPDF_WIN_CMD_FIND_REGEX: return st->regex != 0;
        default: return 0;
    }
}

/* --- the Win32 half, in spdf_win_menu.cpp --------------------------------
 *
 * Handles are void* so this header needs no <windows.h>; every one of them is
 * an HMENU or an HWND and is documented as such at the parameter. */

/* Builds the whole bar from the table above. NULL on failure, which the caller
 * treats as "no menu bar" rather than as a fatal error: a viewer with no menu is
 * still a viewer. */
void* spdf_win_menu_create(void);
void spdf_win_menu_destroy(void* hmenu);

/* Applies the check marks and the greying. Cheap enough to call after every
 * command; it is a few CheckMenuItem/EnableMenuItem calls. */
void spdf_win_menu_sync(void* hmenu, const SpdfWinMenuState* state);

/* The tab strip's overflow `...`. Shows every tab, radio-marks the selected one,
 * and returns the index the user chose or -1. Modal: TrackPopupMenu runs its own
 * loop, which is why this is a call and not an event. */
int spdf_win_menu_tab_overflow(void* hwnd, const wchar_t* const* titles, int count, int selected, int screen_x,
                               int screen_y);

/* Ctrl+O / the strip's `+` / the File menu. IFileOpenDialog, with the PDF and
 * e-book types this app opens. Returns 1 and fills `out_path` (UTF-16, NUL
 * terminated), or 0 when the user cancelled or the dialog could not be created.
 *
 * NATIVE ON PURPOSE. portable/docs/windows-port-handoff.md section 4: "Picking a
 * file has to hand the selection back to the app; no external file manager
 * can." */
int spdf_win_menu_open_dialog(void* hwnd, wchar_t* out_path, int out_len);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_MENU_H */
