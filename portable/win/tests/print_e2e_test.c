/* print_e2e_test.c — A REAL PRINT JOB, from the document to a printed sheet,
 * through the shipping loop and out to a file that is opened again.
 *
 * WHY THIS FILE EXISTS. Every other print test stops short of printing.
 * print_math_test.c is arithmetic, print_differential.c compares that
 * arithmetic against the GTK original, print_scaling_dialog_test.c drives the
 * Scaling page's pure half, and light_theme_test.c puts ONE page on a memory
 * DC. None of them ever asks a printer for anything, so the sentence
 * spdf_win_print.h used to carry -- "spdf_win_print_document() is not
 * exercised end to end here" -- stayed true through the whole port.
 *
 * WHAT WAS IN THE WAY, and it was not the workstation being locked. On this
 * host (Windows 11 Pro 26200) PrintDlgExW with a valid hwndOwner never returns
 * and creates no window; with a NULL one it fails at once with E_HANDLE. The
 * sweep that established that, and the correction it forced -- the CLASSIC
 * PrintDlgW works perfectly well here, so it is PrintDlgExW and not comdlg32
 * that is broken -- are portable/win/tests/print_dialog_probe.c and
 * portable/docs/windows-print-dialog.md. What the app does about it is
 * spdf_win_print_dialog.h: a watchdog, and its own dialog behind it.
 *
 * SO THE DIALOG IS THE ONE THING THIS SKIPS, and everything after it is real.
 * spdf_win_print_run_job() is the whole job -- the paper conversion from the
 * device's caps, StartDoc, StartPage, the render, StretchDIBits, EndPage,
 * EndDoc -- and it is what spdf_win_print_document_ex() itself calls once the
 * reader presses Print. This suite hands it a REAL printer DC for Microsoft
 * Print to PDF and a real output file, then OPENS THE RESULT THROUGH THE CORE
 * and renders a page out of it. A job that starts and produces nothing, or
 * produces bytes MuPDF will not read, fails here.
 *
 * DOCINFO::lpszOutput IS WHY NO DIALOG APPEARS. Microsoft Print to PDF is
 * bound to PORTPROMPT:, which asks the user where to save; naming an output
 * file in the DOCINFO overrides the port and the driver writes straight there
 * and asks nothing. That is a documented StartDoc parameter, not a trick, and
 * it is the reason a print job can be driven with nobody at the keyboard.
 *
 * THREE JOBS, EACH ANSWERING SOMETHING THE OTHERS CANNOT.
 *   1. Fit, two sheets: the job runs, the file is a PDF the core reopens, and
 *      there is ink on it. Two sheets rather than one because a single page
 *      passes even when StartPage/EndPage sit outside the loop.
 *   2. Custom 25%: less ink on the same paper, so the SCALING CHOICE -- the
 *      thing the unshowable Scaling tab edits -- demonstrably reaches paper.
 *   3. A landscape Letter DEVMODE: the printed sheet comes back 792 x 612 pt,
 *      so the DRIVER's orientation and paper size reach the placement through
 *      GetDeviceCaps. That is the only part of the dialog's OUTPUT that can be
 *      reproduced without the dialog.
 *
 * NOTHING IS WRITTEN NEAR THE USER'S DOCUMENTS. The output goes to %TEMP% and
 * is deleted at the end, whether the checks passed or not.
 *
 * HONEST SKIP, NOT A SILENT PASS. A machine without Microsoft Print to PDF
 * prints nothing and says so with SKIP and the OS error; there is no other
 * printer this test may use, because the alternative is paper. The harness
 * cannot record a case as blocked from inside the case, so a skip exits 0 --
 * and prints the reason on its own line so a run that skipped is not mistaken
 * for a run that printed.
 */
/* spdf-test-sources: portable/win/src/spdf_win_print.cpp portable/win/src/spdf_win_export.cpp portable/win/src/spdf_win_clipboard_page.cpp portable/win/src/spdf_win_selection.cpp portable/core/shenzhen_pdf_core.c portable/core/spdf_selection.c portable/core/spdf_selection_support.c portable/core/spdf_recolor.c portable/core/spdf_win_compat.c portable/win/src/spdf_win_open.c portable/core/spdf_markdown.c portable/core/spdf_markdown_support.c portable/core/spdf_markdown_html.c portable/core/spdf_markdown_lang.c portable/core/spdf_markdown_lex.c portable/core/spdf_markdown_math.c portable/core/spdf_markdown_open.c ext/md4c/md4c.c */
/* spdf-test-args: portable/win/tests/fixtures/outline.pdf */
/* spdf-test-needs: mupdf */

#include "spdf_win_open.h"
#include "spdf_win_print.h"

#include <winspool.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* DocumentPropertiesW, for the landscape/Letter job below. spdf_win_print.cpp
 * needs no such thing -- the dialog hands it a DEVMODE -- so the dependency is
 * declared here rather than in the build. */
#pragma comment(lib, "winspool.lib")

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond)                                                                                                    \
    do {                                                                                                               \
        ++g_checks;                                                                                                    \
        if (!(cond)) {                                                                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);                                                     \
            ++g_failures;                                                                                              \
        }                                                                                                              \
    } while (0)

#define PRINTER_NAME L"Microsoft Print to PDF"

/* The spooler writes the file after EndDoc returns, so the job is finished
 * before the bytes are. Polled rather than slept once: on this machine it took
 * well under a second, but a busy spooler is not a failure of this code. */
static int wait_for_file(const wchar_t* path, int max_ms) {
    int waited = 0;
    for (;;) {
        WIN32_FILE_ATTRIBUTE_DATA st;
        if (GetFileAttributesExW(path, GetFileExInfoStandard, &st) && st.nFileSizeLow + st.nFileSizeHigh > 0)
            return 1;
        if (waited >= max_ms) return 0;
        Sleep(100);
        waited += 100;
    }
}

/* Non-background pixels on a page, at a fixed zoom: the amount of ink on the
 * sheet. Background is taken from the top-left pixel, which on a printed sheet
 * is paper by construction. -1 when the page could not be rendered. */
static long ink_on_page(spdf_document* doc, int page_index) {
    spdf_bitmap bmp;
    char err[512] = {0};
    long ink = 0;
    size_t i, n;
    memset(&bmp, 0, sizeof(bmp));
    if (!spdf_render_page_rgba(doc, page_index, 0.5f, &bmp, err, sizeof(err)) || !bmp.rgba || bmp.width <= 0 ||
        bmp.height <= 0) {
        printf("print_e2e: render of page %d failed: %s\n", page_index, err);
        spdf_free_bitmap(&bmp);
        return -1;
    }
    n = (size_t)bmp.height * (size_t)bmp.stride;
    for (i = 0; i + 3 < n; i += 4)
        if (bmp.rgba[i] != bmp.rgba[0] || bmp.rgba[i + 1] != bmp.rgba[1] || bmp.rgba[i + 2] != bmp.rgba[2]) ++ink;
    spdf_free_bitmap(&bmp);
    return ink;
}

/* One real print job to `out_path`, then the ink on its first sheet. The
 * printed PDF is reopened THROUGH THE CORE, which is the only way to know that
 * what the driver wrote is a document and not just bytes. -1 on any failure,
 * with the reason printed. */
static long print_and_measure(HDC dc, spdf_document* doc, const wchar_t* out_path, const int* pages, int page_count,
                              spdf_win_print_scaling_mode mode, double custom_scale, int* out_sheets, float* out_w,
                              float* out_h) {
    char err[512] = {0};
    char open_err[512] = {0};
    char out_utf8[MAX_PATH * 4];
    spdf_document* printed = NULL;
    spdf_win_print_status status;
    long ink;

    if (out_sheets) *out_sheets = -1;
    if (out_w) *out_w = 0.0f;
    if (out_h) *out_h = 0.0f;
    DeleteFileW(out_path); /* a leftover from a killed run must not be read as output */
    status = spdf_win_print_run_job(dc, doc, L"print_e2e_test", out_path, pages, page_count, 1, mode, custom_scale,
                                    err, sizeof(err));
    if (status != SPDF_WIN_PRINT_OK) {
        printf("print_e2e: job status=%d err=%s\n", (int)status, err);
        return -1;
    }
    if (err[0] != '\0') {
        printf("print_e2e: job reported OK but left err=%s\n", err);
        return -1;
    }
    if (!wait_for_file(out_path, 30000)) {
        printf("print_e2e: the spooler wrote no file within 30 s\n");
        return -1;
    }
    if (WideCharToMultiByte(CP_UTF8, 0, out_path, -1, out_utf8, (int)sizeof(out_utf8), NULL, NULL) <= 0) return -1;
    printed = spdf_win_open_document(out_utf8, open_err, sizeof(open_err));
    if (!printed) {
        printf("print_e2e: the printed PDF would not reopen: %s\n", open_err);
        return -1;
    }
    if (out_sheets) *out_sheets = spdf_page_count(printed);
    if (out_w && out_h) {
        char serr[512] = {0};
        if (!spdf_page_size(printed, 0, out_w, out_h, serr, sizeof(serr)))
            printf("print_e2e: could not measure the printed sheet: %s\n", serr);
    }
    ink = ink_on_page(printed, 0);
    spdf_close(printed);
    return ink;
}

/* A printer DC with the DRIVER'S OWN page choice changed -- the part
 * PrintDlgEx would have chosen for us. The dialog would hand its hDevMode to
 * CreateDC; here the DEVMODE is fetched from the driver, two fields are set on
 * it, and it is handed over the same way -- which is also exactly what the
 * in-app dialog's Properties button ends up doing
 * (spdf_win_print_dialog_run.cpp). NULL when the driver will not produce one,
 * which is a skip and not a failure. */
static HDC printer_dc_with(short orientation, short paper_size) {
    HANDLE printer = NULL;
    DEVMODEW* dm = NULL;
    HDC dc = NULL;
    LONG bytes;

    if (!OpenPrinterW((LPWSTR)PRINTER_NAME, &printer, NULL) || !printer) return NULL;
    bytes = DocumentPropertiesW(NULL, printer, (LPWSTR)PRINTER_NAME, NULL, NULL, 0);
    if (bytes > 0) {
        dm = (DEVMODEW*)calloc(1, (size_t)bytes);
        if (dm && DocumentPropertiesW(NULL, printer, (LPWSTR)PRINTER_NAME, dm, NULL, DM_OUT_BUFFER) == IDOK) {
            dm->dmFields |= DM_ORIENTATION | DM_PAPERSIZE;
            dm->dmOrientation = orientation;
            dm->dmPaperSize = paper_size;
            /* Back through the driver so it can reconcile the two fields with
             * everything else in the DEVMODE -- the same round trip the dialog
             * makes when the reader picks a paper size. */
            if (DocumentPropertiesW(NULL, printer, (LPWSTR)PRINTER_NAME, dm, dm,
                                    DM_IN_BUFFER | DM_OUT_BUFFER) == IDOK)
                dc = CreateDCW(L"WINSPOOL", PRINTER_NAME, NULL, dm);
        }
    }
    free(dm);
    ClosePrinter(printer);
    return dc;
}

int main(int argc, char** argv) {
    const char* fixture = argc > 1 ? argv[1] : "portable/win/tests/fixtures/outline.pdf";
    wchar_t out_path[MAX_PATH];
    wchar_t temp_dir[MAX_PATH];
    char open_err[512] = {0};
    spdf_document* doc = NULL;
    HDC dc = NULL;
    long fit_ink, small_ink, land_ink;
    int sheets = -1;
    int pages[2];
    int page_count;
    float sheet_w = 0.0f, sheet_h = 0.0f;
    float land_w = 0.0f, land_h = 0.0f;

    doc = spdf_win_open_document(fixture, open_err, sizeof(open_err));
    if (!doc) {
        printf("FAIL could not open %s: %s\n", fixture, open_err);
        return 1;
    }
    page_count = spdf_page_count(doc);
    CHECK(page_count >= 1);
    CHECK(spdf_win_print_allowed(doc));

    /* A device context for a printer that exists, by name -- no dialog, no
     * DEVMODE of our own, the driver's defaults. */
    dc = CreateDCW(L"WINSPOOL", PRINTER_NAME, NULL, NULL);
    if (!dc) {
        printf("SKIP no printer named \"Microsoft Print to PDF\", GetLastError=%lu\n", (unsigned long)GetLastError());
        spdf_close(doc);
        return 0;
    }

    if (!GetTempPathW((DWORD)(sizeof(temp_dir) / sizeof(temp_dir[0])), temp_dir)) {
        printf("SKIP GetTempPathW failed, GetLastError=%lu\n", (unsigned long)GetLastError());
        DeleteDC(dc);
        spdf_close(doc);
        return 0;
    }
    _snwprintf_s(out_path, sizeof(out_path) / sizeof(out_path[0]), _TRUNCATE, L"%sspdf-print-e2e-%lu.pdf", temp_dir,
                 (unsigned long)GetCurrentProcessId());

    /* TWO PAGES, not one: a single page would pass even if StartPage/EndPage
     * were called once outside the loop, which is exactly the shape of mistake
     * that makes a multi-page print produce one sheet. */
    pages[0] = 0;
    pages[1] = page_count > 1 ? 1 : 0;

    /* JOB ONE: Fit, the default. Everything that has to happen for a print to
     * mean anything happens here -- the job starts, both sheets come out, the
     * file the driver wrote is a PDF the core can open, and there is ink on
     * it. Ink is the check that a parseable pair of BLANK sheets cannot pass. */
    fit_ink = print_and_measure(dc, doc, out_path, pages, 2, SPDF_WIN_PRINT_SCALING_FIT, 1.0, &sheets, &sheet_w,
                                &sheet_h);
    CHECK(sheets == 2);
    CHECK(fit_ink > 0);
    /* The driver's default here is portrait; the landscape job below is only
     * meaningful against that. */
    CHECK(sheet_h > sheet_w);
    printf("print_e2e: default sheet %.1f x %.1f pt\n", (double)sheet_w, (double)sheet_h);

    /* JOB TWO: THE SCALING CHOICE, PROVEN ON PAPER. PrintDlgEx's Scaling tab
     * cannot be shown on this machine (see the header), so the choice it edits
     * -- the same three radios the in-app dialog offers -- is passed straight
     * to the job instead, and a quarter-size page must
     * leave visibly less ink on the same paper than Fit does. Without this,
     * every scaling test in this port stops at the arithmetic and nothing
     * anywhere shows the number reaching a printer. A third is a wide margin
     * around the 1/16 of the area that 25% linear scaling predicts; the point
     * is the direction and the magnitude, not a pixel count. */
    small_ink = print_and_measure(dc, doc, out_path, pages, 2, SPDF_WIN_PRINT_SCALING_CUSTOM, 0.25, &sheets, NULL,
                                  NULL);
    CHECK(sheets == 2);
    CHECK(small_ink > 0);
    if (fit_ink > 0 && small_ink > 0) {
        printf("print_e2e: ink fit=%ld custom25=%ld\n", fit_ink, small_ink);
        CHECK(small_ink < fit_ink / 3);
    }

    /* JOB THREE: THE DRIVER'S OWN PAGE CHOICE, ALSO ON PAPER. Orientation and
     * paper size are the print dialog's, not this app's -- they arrive as a
     * DEVMODE and reach the job only through GetDeviceCaps(HORZRES/VERTRES) in
     * spdf_win_print_run_job's paper conversion. So a LANDSCAPE LETTER DEVMODE
     * must come out as a landscape Letter sheet with the page fitted to it: if
     * the conversion ignored the caps, or transposed them, the sheet would
     * still be portrait A4 and every other check here would pass. This is the
     * one part of the dialog's output that can be reproduced without the
     * dialog. */
    {
        HDC land = printer_dc_with((short)DMORIENT_LANDSCAPE, (short)DMPAPER_LETTER);
        if (!land) {
            printf("SKIP landscape: the driver would not take a DEVMODE, GetLastError=%lu\n",
                   (unsigned long)GetLastError());
        } else {
            land_ink = print_and_measure(land, doc, out_path, pages, 1, SPDF_WIN_PRINT_SCALING_FIT, 1.0, &sheets,
                                         &land_w, &land_h);
            printf("print_e2e: landscape sheet %.1f x %.1f pt, ink=%ld\n", (double)land_w, (double)land_h, land_ink);
            CHECK(sheets == 1);
            CHECK(land_ink > 0);
            /* Wider than tall -- the orientation reached the paper. */
            CHECK(land_w > land_h);
            /* And it is LETTER, not A4: 792 x 612 pt within a point of
             * rounding, and measurably different from the default sheet. */
            CHECK(land_w > 780.0f && land_w < 800.0f);
            CHECK(land_h > 600.0f && land_h < 620.0f);
            CHECK(land_w != sheet_w || land_h != sheet_h);
            DeleteDC(land);
        }
    }

    DeleteFileW(out_path);
    DeleteDC(dc);
    spdf_close(doc);
    printf("print_e2e_test: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures ? 1 : 0;
}
