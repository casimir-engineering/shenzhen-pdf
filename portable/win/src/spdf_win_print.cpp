/* spdf_win_print.cpp — see spdf_win_print.h. */

#include "spdf_win_print.h"

#include "spdf_win_clipboard_page.h" /* spdf_win_clipboard_alloc_dib */
#include "spdf_win_export.h"         /* the light-theme rule, UTF-8 paths */
#include "spdf_win_print_scaling.h"  /* the Scaling page, Win32 half */

#include <commdlg.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* PrintDlgEx lives in comdlg32, which build-native.cmd does not list in
 * SYS_LIBS. Declared here rather than there so no other track's build has to
 * change for this one to link. */
#pragma comment(lib, "comdlg32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "ole32.lib")

/* --- permissions ---------------------------------------------------------- */

int spdf_win_print_allowed(spdf_document* doc) {
    return doc && spdf_has_permission(doc, 'p') ? 1 : 0;
}

int spdf_win_print_high_quality_allowed(spdf_document* doc) {
    return doc && spdf_has_permission(doc, 'h') ? 1 : 0;
}

/* --- one page ------------------------------------------------------------- */

int spdf_win_print_page_to_dc(HDC dc, spdf_document* doc, int page_index, const spdf_win_print_paper* paper,
                              spdf_win_print_scaling_mode mode, double custom_scale, int high_quality_allowed,
                              char* err, size_t err_len) {
    float page_w = 0.0f, page_h = 0.0f;
    spdf_win_print_rect dest;
    spdf_win_print_rect src_pt;
    spdf_win_print_rect dst_pt;
    double mode_scale;
    double zoom;
    spdf_rect region;
    spdf_bitmap bitmap;
    HGLOBAL dib;
    unsigned char* base;
    BITMAPINFOHEADER* header;
    int dest_x, dest_y, dest_w, dest_h;
    int drawn;

    if (err && err_len) err[0] = '\0';
    if (!dc || !doc || !paper) return 0;
    if (!spdf_page_size(doc, page_index, &page_w, &page_h, err, err_len)) return 0;

    dest = spdf_win_print_dest_rect(page_w, page_h, paper->imageable_w_pt, paper->imageable_h_pt, mode, custom_scale);
    if (!spdf_win_print_visible_source(&dest, page_w, page_h, paper->imageable_w_pt, paper->imageable_h_pt, &src_pt,
                                       &dst_pt)) {
        /* Nothing of the page lands on the paper. A blank sheet is the honest
         * result, not a failure: the reader asked for a 10% custom scale on a
         * page that then fell outside the printable area, and refusing the
         * whole job would be worse than one empty page. */
        return 1;
    }

    mode_scale = spdf_win_print_mode_scale(page_w, page_h, paper->imageable_w_pt, paper->imageable_h_pt, mode,
                                           custom_scale);
    zoom = spdf_win_print_render_zoom(mode_scale, paper->dpi_x, paper->dpi_y, src_pt.w, src_pt.h,
                                      SPDF_WIN_PRINT_RENDER_BYTE_CAP);
    zoom = spdf_win_print_permission_render_zoom(zoom, mode_scale, high_quality_allowed);

    region.x0 = (float)src_pt.x;
    region.y0 = (float)src_pt.y;
    region.x1 = (float)(src_pt.x + src_pt.w);
    region.y1 = (float)(src_pt.y + src_pt.h);

    memset(&bitmap, 0, sizeof(bitmap));
    /* spdf_win_export_render_flags() and NOTHING ELSE — see spdf_win_export.h.
     * A printed page carries the document's own colours. */
    if (!spdf_render_page_region_rgba_opts(doc, page_index, (float)zoom, region, spdf_win_export_render_flags(), NULL,
                                           &bitmap, err, err_len))
        return 0;

    /* Reuse of the clipboard's DIB packer, deliberately: it is the tested one,
     * it already handles a MuPDF stride wider than width*4, and a second
     * RGBA->BGRA loop in this file would be a second place to get the channel
     * order wrong. v5 = 0 gives a plain BITMAPINFOHEADER, bottom-up, which is
     * what StretchDIBits wants with a positive height. */
    dib = spdf_win_clipboard_alloc_dib(&bitmap, 0, NULL);
    spdf_free_bitmap(&bitmap);
    if (!dib) {
        if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "The page could not be prepared for the printer.");
        return 0;
    }
    base = (unsigned char*)GlobalLock(dib);
    if (!base) {
        GlobalFree(dib);
        return 0;
    }
    header = (BITMAPINFOHEADER*)base;

    /* Paper points -> printer device pixels. The DC's origin is the printable
     * area's top-left (HORZRES/VERTRES describe that area), so no physical
     * offset enters; see spdf_win_print_paper_from_caps(). */
    dest_x = (int)(dst_pt.x * paper->dpi_x / 72.0 + 0.5);
    dest_y = (int)(dst_pt.y * paper->dpi_y / 72.0 + 0.5);
    dest_w = (int)(dst_pt.w * paper->dpi_x / 72.0 + 0.5);
    dest_h = (int)(dst_pt.h * paper->dpi_y / 72.0 + 0.5);
    if (dest_w < 1) dest_w = 1;
    if (dest_h < 1) dest_h = 1;

    SetStretchBltMode(dc, HALFTONE);
    SetBrushOrgEx(dc, 0, 0, NULL);
    drawn = StretchDIBits(dc, dest_x, dest_y, dest_w, dest_h, 0, 0, header->biWidth, header->biHeight,
                          base + sizeof(BITMAPINFOHEADER), (const BITMAPINFO*)header, DIB_RGB_COLORS, SRCCOPY);
    GlobalUnlock(dib);
    GlobalFree(dib);
    if (drawn == GDI_ERROR) {
        if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "The printer driver rejected the page.");
        return 0;
    }
    return 1;
}

/* --- the job -------------------------------------------------------------- */

/* The pages the dialog asked for, as 0-based indices. Split out so the range
 * translation is one short function with no printing in it; the expansion
 * itself is spdf_win_print_expand_ranges(), which the differential and
 * print_math_test.c both drive. */
static int print_selected_pages(const PRINTDLGEXW* pd, int page_count, int** out) {
    spdf_win_print_page_range stack_ranges[16];
    spdf_win_print_page_range* ranges = NULL;
    int range_count = 0;
    int* pages;
    int written;
    DWORD i;

    *out = NULL;
    if (page_count <= 0) return 0;
    if ((pd->Flags & PD_PAGENUMS) && pd->nPageRanges > 0 && pd->lpPageRanges) {
        range_count = (int)pd->nPageRanges;
        if (range_count > (int)(sizeof(stack_ranges) / sizeof(stack_ranges[0])))
            range_count = (int)(sizeof(stack_ranges) / sizeof(stack_ranges[0]));
        for (i = 0; i < (DWORD)range_count; ++i) {
            stack_ranges[i].from = (int)pd->lpPageRanges[i].nFromPage;
            stack_ranges[i].to = (int)pd->lpPageRanges[i].nToPage;
        }
        ranges = stack_ranges;
    }
    pages = (int*)malloc(sizeof(int) * (size_t)page_count);
    if (!pages) return 0;
    written = spdf_win_print_expand_ranges(ranges, range_count, page_count, pages, page_count);
    if (written <= 0) {
        free(pages);
        return 0;
    }
    *out = pages;
    return written;
}

spdf_win_print_status spdf_win_print_document(HWND parent, spdf_document* doc, const wchar_t* doc_path,
                                              spdf_win_print_scaling_mode mode, double custom_scale, char* err,
                                              size_t err_len) {
    spdf_win_print_choice choice;
    choice.mode = mode;
    choice.custom_scale = custom_scale;
    return spdf_win_print_document_ex(parent, doc, doc_path, &choice, err, err_len);
}

spdf_win_print_status spdf_win_print_document_ex(HWND parent, spdf_document* doc, const wchar_t* doc_path,
                                                 spdf_win_print_choice* choice, char* err, size_t err_len) {
    PRINTDLGEXW pd;
    /* THE SCALING PAGE. `shown` is what the dialog edits, so a cancel leaves the
     * caller's `choice` as it was; on Print it is copied back. The template
     * and the choice must outlive PrintDlgEx, which is why both are here. */
    spdf_win_print_tpl tpl;
    spdf_win_print_choice fallback;
    spdf_win_print_choice shown;
    HPROPSHEETPAGE page = NULL;
    spdf_win_print_scaling_mode mode;
    double custom_scale;
    PRINTPAGERANGE ranges[16];
    DOCINFOW info;
    spdf_win_print_paper paper;
    spdf_document* job_doc = NULL;
    spdf_document* own_doc = NULL;
    char utf8[MAX_PATH * 4];
    char open_err[512] = "";
    int* pages = NULL;
    int page_count;
    int selected = 0;
    int copies;
    int copy;
    int i;
    HRESULT hr;
    spdf_win_print_status status = SPDF_WIN_PRINT_FAILED;

    if (err && err_len) err[0] = '\0';
    if (!doc) return SPDF_WIN_PRINT_NO_DOCUMENT;
    if (!choice) {
        fallback.mode = SPDF_WIN_PRINT_SCALING_FIT;
        fallback.custom_scale = 1.0;
        choice = &fallback;
    }
    shown = *choice;
    shown.custom_scale = spdf_win_print_clamp_custom_scale(shown.custom_scale);
    if (!spdf_win_print_allowed(doc)) {
        /* macOS's sentence, verbatim (ShenzhenPDFMac.mm:15574). */
        if (err && err_len)
            _snprintf_s(err, err_len, _TRUNCATE,
                        "Printing is not allowed. This PDF's permissions do not allow printing.");
        return SPDF_WIN_PRINT_NOT_PERMITTED;
    }
    page_count = spdf_page_count(doc);
    if (page_count <= 0) return SPDF_WIN_PRINT_NO_DOCUMENT;

    memset(&pd, 0, sizeof(pd));
    memset(ranges, 0, sizeof(ranges));
    pd.lStructSize = sizeof(pd);
    pd.hwndOwner = parent;
    pd.Flags = PD_RETURNDC | PD_NOSELECTION | PD_NOCURRENTPAGE;
    pd.nStartPage = START_PAGE_GENERAL;
    pd.nMinPage = 1;
    pd.nMaxPage = (WORD)(page_count > 0xFFFF ? 0xFFFF : page_count);
    pd.nCopies = 1;
    pd.nPageRanges = 0;
    pd.nMaxPageRanges = (DWORD)(sizeof(ranges) / sizeof(ranges[0]));
    pd.lpPageRanges = ranges;
    /* Our tab beside the General page. PrintDlgEx owns the page once it has
     * it; a page that could not be built is a dialog without the tab, printing
     * with the choice as given. */
    page = spdf_win_print_scaling_page(&tpl, &shown);
    if (page) {
        pd.nPropertyPages = 1;
        pd.lphPropertyPages = &page;
    }

    hr = PrintDlgExW(&pd);
    if (FAILED(hr)) {
        /* The locked-workstation case, among others. Reported as its own
         * status: this is not the reader cancelling. */
        if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "The print dialog could not be shown.");
        return SPDF_WIN_PRINT_NO_DIALOG;
    }
    if (pd.dwResultAction != PD_RESULT_PRINT || !pd.hDC) {
        if (pd.hDC) DeleteDC(pd.hDC);
        if (pd.hDevMode) GlobalFree(pd.hDevMode);
        if (pd.hDevNames) GlobalFree(pd.hDevNames);
        return SPDF_WIN_PRINT_CANCELLED;
    }
    /* Printing: what the page holds is the reader's choice, for this job and
     * for the caller to remember. */
    *choice = shown;
    mode = shown.mode;
    custom_scale = shown.custom_scale;

    /* The job's own document handle. See spdf_win_print.h; a failure here is
     * not fatal, it just means the job shares the caller's handle, which is
     * safe because everything below runs on this thread. */
    if (doc_path && spdf_win_export_utf8_path(doc_path, utf8, (int)sizeof(utf8)))
        own_doc = spdf_open(utf8, open_err, sizeof(open_err));
    job_doc = own_doc ? own_doc : doc;

    if (!spdf_win_print_paper_from_caps(GetDeviceCaps(pd.hDC, LOGPIXELSX), GetDeviceCaps(pd.hDC, LOGPIXELSY),
                                        GetDeviceCaps(pd.hDC, HORZRES), GetDeviceCaps(pd.hDC, VERTRES), &paper)) {
        if (err && err_len)
            _snprintf_s(err, err_len, _TRUNCATE, "The printer did not report a usable page size.");
        goto cleanup;
    }

    selected = print_selected_pages(&pd, page_count, &pages);
    if (selected <= 0) {
        if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "No pages were selected.");
        status = SPDF_WIN_PRINT_CANCELLED;
        goto cleanup;
    }

    memset(&info, 0, sizeof(info));
    info.cbSize = sizeof(info);
    info.lpszDocName = (doc_path && *doc_path) ? spdf_win_export_file_name(doc_path) : L"Shenzhen PDF";
    if (StartDocW(pd.hDC, &info) <= 0) {
        if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "The print job could not be started.");
        goto cleanup;
    }

    /* PD_COLLATE is the driver's business when it handles copies itself; when
     * it does not, nCopies comes back > 1 and the job repeats the range. */
    copies = pd.nCopies > 0 ? (int)pd.nCopies : 1;
    for (copy = 0; copy < copies; ++copy) {
        for (i = 0; i < selected; ++i) {
            if (StartPage(pd.hDC) <= 0) {
                AbortDoc(pd.hDC);
                if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "The printer stopped accepting pages.");
                goto cleanup;
            }
            if (!spdf_win_print_page_to_dc(pd.hDC, job_doc, pages[i], &paper, mode, custom_scale,
                                           spdf_win_print_high_quality_allowed(job_doc), err, err_len)) {
                EndPage(pd.hDC);
                AbortDoc(pd.hDC);
                goto cleanup;
            }
            if (EndPage(pd.hDC) <= 0) {
                AbortDoc(pd.hDC);
                if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "The printer rejected a finished page.");
                goto cleanup;
            }
        }
    }
    EndDoc(pd.hDC);
    status = SPDF_WIN_PRINT_OK;

cleanup:
    if (pages) free(pages);
    if (own_doc) spdf_close(own_doc);
    if (pd.hDC) DeleteDC(pd.hDC);
    if (pd.hDevMode) GlobalFree(pd.hDevMode);
    if (pd.hDevNames) GlobalFree(pd.hDevNames);
    return status;
}
