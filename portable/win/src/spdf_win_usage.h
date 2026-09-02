#pragma once

/* The --help / bad-usage text, and nothing else.
 *
 * Extracted from spdf_win_main.cpp, which sat at its 500-line cap
 * (tools/file-size-limits.md asks for a focused file rather than a raised cap --
 * the same move spdf_win_headless.h, spdf_win_headless_viewport.h,
 * spdf_win_d2d_png.h and spdf_win_chrome_state.h all made). It is a genuine
 * seam despite being one function: this text is the app's command-line
 * CONTRACT, it is what a reader consults when a flag does not behave, and it is
 * the thing most often forgotten when a flag is added.
 *
 * Kept in sync with the parser by being next to nothing else. If you add a flag
 * to spdf_win_main.cpp, it belongs here in the same change.
 */

static int usage(void) {
    fwprintf(stderr,
             L"usage: ShenzhenPDF.exe [--dark|--light] [--page N] [file.pdf]\n"
             L"       (no file: restores the last session, or opens an empty window)\n"
             L"       ShenzhenPDF.exe --render-png [--dark] <file.pdf> <page> <zoom> <out.png>\n"
             L"       ShenzhenPDF.exe --render-window-png [opts] <file.pdf> <page> <w> <h> <out.png>\n"
             L"\n"
             L"  <page> is 0-BASED, matching the core API and spdf_win_probe.\n"
             L"  opts:  --dark            dark reading theme, images preserved\n"
             L"         --light           light theme; both override the system theme a window follows\n"
             L"         --fit MODE        width (default) | height | page | actual\n"
             L"         --zoom Z          device pixels per PDF point; overrides --fit\n"
             L"         --scroll-x X      viewport pixels, added to the top of <page>\n"
             L"         --scroll-y Y\n"
             L"         --dpi S           device pixels per logical pixel (default 1)\n"
             L"         --zoom-at X,Y     zoom about this viewport point after scrolling\n"
             L"         --zoom-factor F   how much to zoom there (default 2)\n"
             L"         --frames N        render N frames, a viewport apart; last is written\n"
             L"         --chrome          compose the tab strip, toolbar, sidebar and minimap too\n"
             L"         --find Q          run a search for Q, so the frame shows the find chrome\n"
             L"         --find-regex      treat Q as a regular expression\n");
    return 64;
}
