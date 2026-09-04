/* spdf_win_print_dialog.h — the two ways this port asks "print what, where?".
 *
 * WINDOWS' OWN DIALOG IS STILL THE NORMAL PATH, but it is no longer allowed to
 * take the app with it. spdf_win_print_system_dialog() calls PrintDlgExW on a
 * DEDICATED THREAD with its own STA and its own message pump, and watches for a
 * window: if nothing of ours becomes visible within
 * SPDF_WIN_PRINT_DIALOG_WATCHDOG_MS the wait is over, the thread is ABANDONED
 * (never TerminateThread -- see below), and the caller falls back to the
 * in-app dialog in this same header.
 *
 * WHAT WAS MEASURED, on this host (Windows 11 Pro 26200, 2026-09-04), by
 * portable/win/tests/print_dialog_probe.c. The full transcript and the sweep
 * that produced it are portable/docs/windows-print-dialog.md:
 *
 *   PrintDlgExW, hwndOwner = NULL       returns E_HANDLE (0x80070006) at once
 *   PrintDlgExW, a valid hwndOwner      NEVER RETURNS, and creates no window
 *   PrintDlgW  PD_RETURNDC              works: shows "Print", returns TRUE with
 *                                       a 600 dpi printer DC on OK, FALSE on
 *                                       Cancel
 *   PrintDlgW  PD_RETURNDEFAULT         works (no UI, ok=1)
 *   PrintDlgW  PD_PRINTSETUP            works: shows "Print Setup"
 *   PageSetupDlgW                       works: shows "Page Setup"
 *   DocumentPropertiesW DM_IN_PROMPT    works: shows the driver's own sheet
 *
 * So comdlg32 is fine here and only PrintDlgExW is broken -- which corrects the
 * earlier note in spdf_win_print.h that "no comdlg32 print dialog can be shown
 * on this machine". The hang survives every app-level variable worth trying:
 * the worker's apartment (STA, MTA, none), whether it pumps, DPI awareness,
 * the Common Controls 6 activation context the app has and the probe does not,
 * dropping PD_RETURNDC, and having no property page at all. It is not this
 * app's call; it is the hand-off to the Windows 11 print experience.
 *
 * WHY hwndOwner IS CHECKED BEFORE A THREAD IS EVEN STARTED. PRINTDLGEX's
 * hwndOwner "must be a valid window handle; it cannot be NULL", and this host
 * enforces that with E_HANDLE. A NULL parent therefore goes straight to the
 * fallback instead of paying the watchdog for a call that cannot succeed.
 *
 * NEVER TerminateThread. A thread wedged inside comdlg32 holds the loader lock
 * and a COM apartment; killing it corrupts the process heap, which is a worse
 * outcome than the hang it would be trying to cure. So the thread is left
 * running and everything it can still touch -- the PRINTDLGEXW, the page-range
 * array, the property-sheet template and the choice it edits -- lives in ONE
 * heap block owned by whichever side wins an interlocked hand-off, never on the
 * caller's stack. If the call ever does come back, the thread frees the block
 * itself and nobody is waiting.
 *
 * AND IT IS ASKED ONCE. A host whose PrintDlgEx has been abandoned will do it
 * again, so the second Print does not start a second doomed thread: the
 * process-wide state is remembered and every later Print goes straight to the
 * in-app dialog. That is also the single in-flight guard -- a print dialog
 * cannot be opened twice at once.
 *
 * THE IN-APP DIALOG is spdf_win_print_dialog_show(): a plain Win32 window built
 * like spdf_win_properties_dialog.cpp and spdf_win_about.cpp beside it (no
 * resource script, the port's own theming, dark caption through
 * spdf_win_about_dark_caption), offering the four things a reader actually has
 * to choose -- the printer, the copies, the pages and the scale -- plus a
 * Properties button that reaches the DRIVER's own sheet through
 * DocumentPropertiesW DM_IN_PROMPT, which is measured to work here. What comes
 * out is a spdf_win_print_request; spdf_win_print_dialog_run() turns that into
 * a DC and hands it to the proven spdf_win_print_run_job().
 *
 * FOUR FILES, AND WHY. spdf_win_print_dialog_system.cpp is Windows' dialog and
 * the watchdog; spdf_win_print_dialog.cpp is the in-app window;
 * spdf_win_print_dialog_run.cpp is everything about the spooler that needs no
 * window (the printer list, the driver's property sheet, the range, the job);
 * and spdf_win_print_dialog_choose.cpp is only the order the two are asked in
 * and what is remembered afterwards. That last split is not tidiness: it keeps
 * settings.yaml -- and with it the state shell, the YAML codec, the recents
 * store and the watcher -- out of spdf_win_print.cpp, which
 * portable/win/tests/light_theme_test.c links for nothing but one page onto a
 * memory DC.
 */
#ifndef SPDF_WIN_PRINT_DIALOG_H
#define SPDF_WIN_PRINT_DIALOG_H

#include <windows.h>

#include "shenzhen_pdf_core.h"
#include "spdf_win_print.h" /* spdf_win_print_status, spdf_win_print_choice */

#ifdef __cplusplus
extern "C" {
#endif

/* HOW LONG A DIALOG THAT IS GOING TO APPEAR MAY TAKE TO APPEAR. Not how long
 * the reader may take: the clock STOPS the moment a window of ours becomes
 * visible, and after that the wait is unbounded, because a modal dialog waiting
 * for a human is the normal case and must never be cut short. 4 s is generous
 * against the measurements here -- the classic dialog and the driver's property
 * sheet both put a window up in well under a second -- and short enough that a
 * reader on a broken host is not left wondering. */
#define SPDF_WIN_PRINT_DIALOG_WATCHDOG_MS 4000

/* --- Windows' own dialog, watchdogged ------------------------------------- */

/* What PrintDlgEx decided, when it decided anything. */
typedef struct spdf_win_print_system_result {
    HDC dc;                        /* PD_RETURNDC's; the caller DeleteDC()s it */
    int copies;                    /* at least 1 */
    int* pages;                    /* 0-based indices; the caller free()s */
    int page_count;                /* entries in `pages` */
    spdf_win_print_choice choice;  /* what the Scaling tab holds */
} spdf_win_print_system_result;

/* Show Windows' print dialog for a `doc_page_count`-page document, with the
 * Scaling tab preset from `preset`. `parent` is the owner and MUST be non-NULL
 * for this to be attempted at all (see the header).
 *
 *   SPDF_WIN_PRINT_OK        the reader pressed Print; `out` is filled
 *   SPDF_WIN_PRINT_CANCELLED the reader cancelled; `err` is empty
 *   SPDF_WIN_PRINT_NO_DIALOG the dialog could not be shown -- the watchdog
 *                            fired, an earlier attempt on this host had
 *                            already been abandoned, PrintDlgEx failed, or
 *                            `parent` was NULL. `err` says which. FALL BACK.
 *   SPDF_WIN_PRINT_FAILED    it printed but handed back nothing usable
 */
spdf_win_print_status spdf_win_print_system_dialog(HWND parent, int doc_page_count,
                                                   const spdf_win_print_choice* preset,
                                                   spdf_win_print_system_result* out, char* err, size_t err_len);

/* 1 when this process has already abandoned a PrintDlgEx thread, i.e. the
 * fallback is now the normal path and is worth explaining to the reader. */
int spdf_win_print_system_dialog_abandoned(void);

/* --- the printers on this machine ----------------------------------------- */

#define SPDF_WIN_PRINT_NAME_MAX 256
#define SPDF_WIN_PRINT_MAX_PRINTERS 64

typedef struct spdf_win_print_printers {
    wchar_t name[SPDF_WIN_PRINT_MAX_PRINTERS][SPDF_WIN_PRINT_NAME_MAX];
    int count;
    int selected; /* the default printer's index, or 0, or -1 when there are none */
} spdf_win_print_printers;

/* Every local and connected printer, from EnumPrintersW, with `selected` set to
 * GetDefaultPrinterW's if it is among them. Returns the count, which is 0 on a
 * machine with no printers at all. */
int spdf_win_print_dialog_printers(spdf_win_print_printers* out);

/* The index of `name` in `list`, or -1. Case-insensitive, because a printer
 * name persisted in settings.yaml comes back from the spooler with whatever
 * case the spooler feels like. */
int spdf_win_print_printers_index_of(const spdf_win_print_printers* list, const wchar_t* name);

/* --- the reader's answer --------------------------------------------------- */

typedef enum spdf_win_print_range_mode {
    SPDF_WIN_PRINT_RANGE_ALL = 0,
    SPDF_WIN_PRINT_RANGE_CURRENT = 1,
    SPDF_WIN_PRINT_RANGE_FROM_TO = 2
} spdf_win_print_range_mode;

typedef struct spdf_win_print_request {
    wchar_t printer[SPDF_WIN_PRINT_NAME_MAX];
    spdf_win_print_range_mode range;
    int from; /* 1-based, inclusive; only read when range is FROM_TO */
    int to;
    int copies;
    spdf_win_print_choice choice;
    /* The DEVMODE the reader edited in Properties, malloc'd, or NULL for the
     * driver's own defaults. Freed by spdf_win_print_request_free(). */
    DEVMODEW* devmode;
} spdf_win_print_request;

void spdf_win_print_request_free(spdf_win_print_request* req);

/* PURE: the request's page range as a Win32-shaped 1-based range for
 * spdf_win_print_expand_ranges(). `current_page` is 0-based, or negative when
 * the caller does not know it -- in which case CURRENT degrades to page 1
 * rather than to an empty job. A FROM_TO whose ends are reversed is swapped,
 * and both ends are clamped into [1, page_count]; ALL returns 0, which is what
 * spdf_win_print_expand_ranges() reads as "the whole document".
 *
 * Returns the number of ranges written (0 or 1). Pure C, no Win32, so
 * portable/win/tests/print_dialog_test.c drives it without a printer. */
int spdf_win_print_dialog_range(const spdf_win_print_request* req, int current_page, int page_count,
                                spdf_win_print_page_range* out);

/* --- the in-app dialog ---------------------------------------------------- */

/* Show it, modal against `parent` only (never the whole thread -- this app is
 * tabbed and multi-window). `doc_name` titles the job and may be NULL;
 * `current_page` is 0-based, or negative when unknown, in which case the
 * "Current page" choice is greyed out rather than lying about which page it
 * means. `note`, when non-NULL, is one line shown above the buttons -- how the
 * reader is told that Windows' own dialog did not open.
 *
 * `req` is BOTH the preset and the answer: on entry its printer, copies and
 * choice are what the dialog opens with; on Print they are what the reader
 * left. Returns 1 on Print, 0 on cancel or when no window could be created
 * (a locked session, no window station), in which case `err` says so. */
int spdf_win_print_dialog_show(HWND parent, int dark, const wchar_t* doc_name, int page_count, int current_page,
                               const char* note, spdf_win_print_request* req, char* err, size_t err_len);

/* The driver's own property sheet for `printer`: DocumentPropertiesW with
 * DM_IN_PROMPT | DM_IN_BUFFER | DM_OUT_BUFFER, which is the documented way to
 * show it without comdlg32 and is measured to work on this host. `*devmode` is
 * the DEVMODE to open with (NULL for the driver's default) and receives a
 * malloc'd replacement when the reader pressed OK. Returns 1 when the reader
 * pressed OK, 0 on cancel or when the sheet could not be shown. */
int spdf_win_print_dialog_properties(HWND parent, const wchar_t* printer, DEVMODEW** devmode);

/* Everything after Print: a printer DC for `req`'s printer and DEVMODE, the
 * page list from its range, then spdf_win_print_run_job(). `job_name` is what
 * the queue shows. */
spdf_win_print_status spdf_win_print_dialog_run(const spdf_win_print_request* req, spdf_document* doc,
                                                const wchar_t* job_name, int page_count, int current_page, char* err,
                                                size_t err_len);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* SPDF_WIN_PRINT_DIALOG_H */
