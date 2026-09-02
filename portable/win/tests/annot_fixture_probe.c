/* annot_fixture_probe.c — writes a PDF with comments for the headless proof of
 * the annotations track: copies a source PDF to a destination and adds one
 * highlight comment and one text comment through the core's own calls, exactly
 * as the app does minus the dialogs. Not a test (no *_test.c name, so the sweep
 * leaves it alone); build it by hand:
 *
 *   build-native.cmd annot_fixture_probe portable/win/tests/annot_fixture_probe.c \
 *       portable/core/shenzhen_pdf_core.c portable/core/spdf_selection.c \
 *       portable/core/spdf_selection_support.c portable/core/spdf_recolor.c \
 *       portable/core/spdf_win_compat.c
 *   annot_fixture_probe.exe <source.pdf> <dest.pdf>
 *
 * then --render-window-png --chrome the destination. Exit 0 on success. */
#include "shenzhen_pdf_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int copy_file(const char* from, const char* to) {
    FILE* in = fopen(from, "rb");
    FILE* out = in ? fopen(to, "wb") : NULL;
    char buf[65536];
    size_t n;
    if (!in || !out) {
        if (in) fclose(in);
        if (out) fclose(out);
        return 0;
    }
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0) fwrite(buf, 1, n, out);
    fclose(in);
    fclose(out);
    return 1;
}

int main(int argc, char** argv) {
    char err[512] = {0};
    spdf_document* doc;
    spdf_rect rects[2];
    spdf_comments comments;
    if (argc < 3) {
        fprintf(stderr, "usage: annot_fixture_probe <source.pdf> <dest.pdf>\n");
        return 64;
    }
    if (!copy_file(argv[1], argv[2])) {
        fprintf(stderr, "could not copy %s to %s\n", argv[1], argv[2]);
        return 1;
    }
    doc = spdf_open(argv[2], err, sizeof(err));
    if (!doc) {
        fprintf(stderr, "open: %s\n", err);
        return 1;
    }
    rects[0].x0 = 72.0f;
    rects[0].y0 = 100.0f;
    rects[0].x1 = 300.0f;
    rects[0].y1 = 112.0f;
    rects[1].x0 = 72.0f;
    rects[1].y0 = 114.0f;
    rects[1].x1 = 200.0f;
    rects[1].y1 = 126.0f;
    if (!spdf_add_highlight_comment(doc, 0, rects, 2, "Check this figure against the appendix", "Rapha\xc3\xabl", err,
                                    sizeof(err)) ||
        !spdf_add_text_comment(doc, 0, 380.0f, 300.0f, "A note in the margin", "Tester", err, sizeof(err)) ||
        !spdf_save_document(doc, argv[2], err, sizeof(err))) {
        fprintf(stderr, "write: %s\n", err);
        spdf_close(doc);
        return 1;
    }
    spdf_close(doc);
    doc = spdf_open(argv[2], err, sizeof(err));
    if (!doc || !spdf_load_comments(doc, &comments, err, sizeof(err))) {
        fprintf(stderr, "reload: %s\n", err);
        return 1;
    }
    printf("%d comments in %s\n", comments.count, argv[2]);
    spdf_free_comments(&comments);
    spdf_close(doc);
    return 0;
}
