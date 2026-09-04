/* spdf_win_print.h — printing: the Win32 print dialog, and the loop that
 * renders the chosen pages through the core at the printer's own resolution.
 *
 * THE ARITHMETIC IS NOT HERE. Scaling mode, the destination rect on the paper,
 * the visible-source split for oversized pages, the dpi/memory render-zoom
 * policy and the page-range expansion all live in spdf_win_print_math.h, which
 * is pure doubles and is compared function by function against the GTK4
 * original by portable/win/tests/print_differential.c. What is left here is
 * exactly the part that needs a printer: the dialog, the DC, StretchDIBits and
 * the StartDoc/StartPage/EndPage/EndDoc envelope.
 *
 * PERMISSION. A document whose 'p' flag is 0 IS NOT PRINTED, and the reader is
 * told why. That is the macOS behaviour verbatim — ShenzhenPDFMac.mm:15574
 * refuses with "Printing is not allowed / This PDF's permissions do not allow
 * printing." before the print panel is even built — and it is the one place
 * this product does honour a PDF permission bit for a whole action. (Copy does
 * not: 'c' returns 1 unconditionally, shenzhen_pdf_core.h:209-214. Print, edit
 * and annotate answer the document's own flags.) The SEPARATE high-quality
 * flag 'h' does not block the job; it caps the render at 150 dpi, exactly as
 * spdf_print_permission_render_zoom does on GTK and as
 * `spdf_has_permission(_doc, 'h') ? 1200.0 : 150.0` does on macOS.
 *
 * THE LIGHT-THEME RULE. Every page is rendered through
 * spdf_win_export_render_flags(), i.e. SPDF_RENDER_DEFAULT. A printed page
 * carrying our dark paper would be wrong on paper in a way it is not even on
 * screen. See spdf_win_export.h; the regression is
 * portable/win/tests/light_theme_test.c.
 *
 * ITS OWN DOCUMENT HANDLE. The core allows ONE spdf_document per thread with no
 * locking inside (shenzhen_pdf_core.c:40-43), so the job opens its own handle
 * from the path rather than borrowing the tab's — the same rule the render
 * workers, the thumbnail store, the GTK print job (spdf_print.c's strategy
 * note) and the GTK search worker all follow. It also means printing cannot
 * evict the reading document's cached page lists. A document that cannot be
 * reopened (a password-protected one, whose password this function does not
 * have) falls back to the caller's handle, which is correct because the job
 * then runs on the calling thread anyway.
 *
 * ON WHICH THREAD. The calling one. macOS runs the operation modally and GTK
 * renders synchronously in draw-page for the same reason: memory stays bounded
 * to ONE page region bitmap regardless of how many pages were selected, and a
 * background job would need either the whole range at printer resolution in RAM
 * or a disk spool. Moving it to a worker later needs no change to any of the
 * arithmetic — it needs the private document handle this file already opens.
 *
 * WHAT CANNOT BE DRIVEN HERE, AND IT IS NOT THE PRINTING. Measured on an
 * unlocked Windows 11 Pro 26200 session, 2026-09-03: NO comdlg32 print dialog
 * can be shown on that machine. spdf_win_print_document_ex() reaches
 * PrintDlgExW and PrintDlgExW never returns — no window is created, nothing is
 * shown, and the app can only be killed. That is NOT this file calling it
 * wrongly: an independent process, its own STA, its own pumping message loop,
 * the same flags and the same page-range array, hangs identically inside
 * PrintDlgExW; so does the CLASSIC PrintDlgW with PD_NOPAGENUMS and no ranges
 * at all. The hung process has windows.internal.shellcommon.PrintExperience.dll
 * and Print.PrintSupport.Source.dll loaded, i.e. comdlg32 has handed off to the
 * Windows 11 print experience and that hand-off does not come back. One machine
 * is not every machine, but the app's call is exonerated and the dialog is the
 * only part that cannot be reached.
 *
 * SO THE JOB IS DRIVEN WITHOUT IT. spdf_win_print_run_job() below is everything
 * after the dialog — the paper conversion, StartDoc, the per-page loop,
 * EndDoc — against a DC the caller supplies, and
 * portable/win/tests/print_e2e_test.c hands it a real Microsoft Print to PDF
 * device with a real output file and reopens the PDF that comes out through the
 * core. That is a genuine end-to-end print job through the shipping loop rather
 * than a copy of it; what is left untested on this host is PrintDlgEx choosing
 * the printer and the pages, which is Windows' own dialog.
 */
#ifndef SPDF_WIN_PRINT_H
#define SPDF_WIN_PRINT_H

#include <windows.h>

#include "shenzhen_pdf_core.h"
#include "spdf_win_print_math.h"
#define SPDF_WIN_PRINT_SCALING_PURE /* the page itself is the .cpp's business */
#include "spdf_win_print_scaling.h" /* spdf_win_print_choice */
#undef SPDF_WIN_PRINT_SCALING_PURE

#ifdef __cplusplus
extern "C" {
#endif

/* Why a print request was refused before any dialog appeared. Named values
 * rather than a bare 0 so the caller can say the right sentence: "this document
 * forbids printing" and "your session is locked" are different problems and a
 * reader who is told the wrong one will go looking in the wrong place. */
typedef enum spdf_win_print_status {
    SPDF_WIN_PRINT_OK = 0,
    SPDF_WIN_PRINT_NO_DOCUMENT = 1,
    SPDF_WIN_PRINT_NOT_PERMITTED = 2, /* spdf_has_permission(doc, 'p') == 0 */
    SPDF_WIN_PRINT_CANCELLED = 3,
    SPDF_WIN_PRINT_NO_DIALOG = 4, /* PrintDlgEx could not be shown at all */
    SPDF_WIN_PRINT_FAILED = 5     /* the job started and something went wrong */
} spdf_win_print_status;

/* The permission verdict, on its own, so the shell can grey the menu item out
 * without opening anything. 1 when the document may be printed. A NULL document
 * is not printable. Note this is 'p'; 'h' only caps the resolution. */
int spdf_win_print_allowed(spdf_document* doc);

/* 1 when the document allows HIGH-QUALITY printing ('h'). A document that
 * allows printing but not high-quality printing prints at up to 150 dpi. */
int spdf_win_print_high_quality_allowed(spdf_document* doc);

/* Show the print dialog and print. `doc_path` is used to open the job's own
 * document handle and to name the job in the print queue. `err` receives a
 * sentence suitable for showing the reader; it is empty on cancellation.
 *
 * The scaling mode and custom scale come from the caller (the shell persists
 * them as "printScalingMode" / "printCustomScale", the same keys macOS and GTK
 * write); pass SPDF_WIN_PRINT_SCALING_FIT and 1.0 for the defaults. */
spdf_win_print_status spdf_win_print_document(HWND parent, spdf_document* doc, const wchar_t* doc_path,
                                              spdf_win_print_scaling_mode mode, double custom_scale, char* err,
                                              size_t err_len);

/* The same, WITH THE SCALING PAGE: the dialog gets a "Scaling" tab preset from
 * `choice` (spdf_win_print_scaling.h), the job prints with what the reader
 * chose, and `choice` holds that on return -- the caller persists it as
 * printScalingMode / printCustomScale when the status is OK. On a cancel
 * `choice` is left as it was. This is the entry point the shell uses; the one
 * above is for a caller that has already decided. */
spdf_win_print_status spdf_win_print_document_ex(HWND parent, spdf_document* doc, const wchar_t* doc_path,
                                                 spdf_win_print_choice* choice, char* err, size_t err_len);

/* THE JOB, WITHOUT THE DIALOG: everything spdf_win_print_document_ex() does
 * once the reader has pressed Print, against a DC the caller already has.
 *
 * `dc` is a printer DC (the dialog's PD_RETURNDC one, or a CreateDCW on a
 * printer name). `job_name` is what the print queue shows; NULL or "" is
 * "Shenzhen PDF". `out_file` is DOCINFO::lpszOutput — NULL prints to the port
 * the DC names, a path makes the driver write there and ask nothing, which is
 * how a Microsoft Print to PDF job runs with no Save dialog of its own.
 * `pages` is 0-based indices, `copies` at least 1. `mode`/`custom_scale` are
 * the reader's scaling choice.
 *
 * Returns OK, or FAILED with a sentence in `err`. On any failure after StartDoc
 * the job is AbortDoc'd, so a half-printed document never reaches the queue. */
spdf_win_print_status spdf_win_print_run_job(HDC dc, spdf_document* doc, const wchar_t* job_name,
                                             const wchar_t* out_file, const int* pages, int page_count, int copies,
                                             spdf_win_print_scaling_mode mode, double custom_scale, char* err,
                                             size_t err_len);

/* One page onto a device context, at `paper`'s resolution, placed by the
 * arithmetic in spdf_win_print_math.h. Split out of the job loop so it can be
 * pointed at ANY DC — which is how it is checked without a printer: a memory DC
 * over a known-size DIB section gives the same call the same way, and that is
 * what light_theme_test.c uses to prove the printed pixels are the document's
 * own colours. Returns 1 on success. */
int spdf_win_print_page_to_dc(HDC dc, spdf_document* doc, int page_index, const spdf_win_print_paper* paper,
                              spdf_win_print_scaling_mode mode, double custom_scale, int high_quality_allowed,
                              char* err, size_t err_len);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* SPDF_WIN_PRINT_H */
