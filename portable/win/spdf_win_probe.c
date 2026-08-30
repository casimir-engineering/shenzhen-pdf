/* spdf_win_probe -- the cross-host conformance probe for the Windows port.
 *
 *   spdf_win_probe <document> [page-index] [zoom] [out.png] [plain|dark|dark-images]
 *
 * WHAT THIS IS FOR. The Windows port has no screen an agent can look at, so the
 * question "does portable/core behave the same on Windows as it does on macOS?"
 * has to be answered by text. This program exercises the shipping core entry
 * points -- spdf_open, spdf_page_count, spdf_page_size,
 * spdf_render_page_rgba_opts -- and prints a report designed for exactly one
 * consumer: `diff`. Build it on macOS with clang, build it in the guest with
 * cl.exe, run both against the same fixture, diff the two transcripts. A clean
 * diff is a real, specific proof; a dirty one points at the line that differs.
 *
 * THEREFORE EVERY LINE OF OUTPUT MUST BE DETERMINISTIC ACROSS HOSTS:
 *   - no timings (that is why there is no clock_gettime here, which would not
 *     compile under the MSVC UCRT anyway -- see the port plan's risk 13),
 *   - no pointers, no sizes of host types, no locale-dependent formatting,
 *   - no full paths: only the basename, split on BOTH '/' and '\\',
 *   - all statistics are integer sums, never floating-point means, so the last
 *     digit cannot drift between two compilers' rounding.
 * If you add a line, ask first whether two different compilers on two different
 * operating systems must agree on it exactly. If not, it does not belong here.
 *
 * PORTABILITY RULES OBSERVED HERE: C89-style declarations at the top of each
 * block (MSVC in C mode is stricter than clang), no POSIX headers, no VLAs, no
 * designated initialisers. The only dependencies are portable/core and MuPDF.
 */
#include "shenzhen_pdf_core.h"

#include <mupdf/fitz.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROBE_FORMAT 1

/* How many page sizes to report before summarising. Bounded so the transcript
 * of a 500-page document stays diffable. */
#define MAX_PAGES_LISTED 8

/* The sample grid. 5x5 normalised positions across the rendered bitmap: dense
 * enough that a vertical flip or a channel swap changes many lines, sparse
 * enough that a human can read the diff. */
#define GRID 5

static const char* basename_portable(const char* path) {
    const char* out = path;
    const char* p;
    for (p = path; *p; ++p) {
        if (*p == '/' || *p == '\\') out = p + 1;
    }
    return out;
}

/* FNV-1a over the visible pixels only. The stride padding is deliberately
 * skipped: two hosts may legitimately choose different row padding, and a
 * checksum that folded it in would report a difference where none is visible. */
static void checksum_pixels(const unsigned char* rgba, int w, int h, int stride, char* out, size_t out_len) {
    unsigned long long hash = 1469598103934665603ULL;
    int x, y;

    for (y = 0; y < h; ++y) {
        const unsigned char* row = rgba + (size_t)y * (size_t)stride;
        for (x = 0; x < w * 4; ++x) {
            hash ^= (unsigned long long)row[x];
            hash *= 1099511628211ULL;
        }
    }
    /* Printed as two 32-bit halves: MSVC and clang disagree about %llx vs %I64x
     * in older toolchains, and %08lX of a 32-bit value is portable everywhere. */
    snprintf(out, out_len, "%08lX%08lX", (unsigned long)((hash >> 32) & 0xFFFFFFFFULL),
             (unsigned long)(hash & 0xFFFFFFFFULL));
}

static void write_png(const char* path, const unsigned char* rgba, int w, int h, int stride) {
    fz_context* ctx = fz_new_context(NULL, NULL, FZ_STORE_UNLIMITED);
    int y;

    if (!ctx) {
        fprintf(stderr, "probe: no fitz context for png\n");
        return;
    }
    fz_try(ctx) {
        /* alpha=1: the golden comparison must be able to see the alpha channel.
         * Dropping it here would make the harness structurally unable to detect
         * the premultiplied-alpha class of bug, which is the one this repo has
         * actually hit. */
        fz_pixmap* pix = fz_new_pixmap(ctx, fz_device_rgb(ctx), w, h, NULL, 1);
        for (y = 0; y < h; ++y)
            memcpy(pix->samples + (size_t)y * (size_t)pix->stride, rgba + (size_t)y * (size_t)stride, (size_t)w * 4);
        fz_save_pixmap_as_png(ctx, pix, path);
        fz_drop_pixmap(ctx, pix);
    }
    fz_catch(ctx) { fprintf(stderr, "probe: png write failed: %s\n", fz_caught_message(ctx)); }
    fz_drop_context(ctx);
}

static unsigned flags_from_name(const char* name) {
    if (!name || !strcmp(name, "plain")) return SPDF_RENDER_DEFAULT;
    if (!strcmp(name, "dark")) return SPDF_RENDER_DARK_THEME;
    if (!strcmp(name, "dark-images")) return SPDF_RENDER_DARK_THEME | SPDF_RENDER_PRESERVE_IMAGES;
    return 0xFFFFFFFFu; /* caller reports the usage error */
}

int main(int argc, char** argv) {
    const char* path = argc > 1 ? argv[1] : NULL;
    int page = argc > 2 ? atoi(argv[2]) : 0;
    double zoom = argc > 3 ? atof(argv[3]) : 2.0;
    const char* png_path = (argc > 4 && argv[4][0] && strcmp(argv[4], "-")) ? argv[4] : NULL;
    const char* mode = argc > 5 ? argv[5] : "plain";
    unsigned flags;
    char err[512];
    spdf_document* doc;
    spdf_bitmap bitmap;
    int pages, i;
    int gx, gy;
    unsigned long long sum_r = 0, sum_g = 0, sum_b = 0, sum_a = 0;
    unsigned long long nonopaque = 0, transparent_colored = 0, premul_violations = 0, partial = 0;
    int amin = 255, amax = 0;
    char digest[32];

    if (!path) {
        fprintf(stderr, "usage: spdf_win_probe <document> [page-index] [zoom] [out.png] [plain|dark|dark-images]\n");
        return 2;
    }
    flags = flags_from_name(mode);
    if (flags == 0xFFFFFFFFu) {
        fprintf(stderr, "probe: unknown render mode '%s'\n", mode);
        return 2;
    }

    /* The header is printed before anything can fail so that a truncated
     * transcript is still recognisable as this program's output. */
    printf("spdf-probe %d\n", PROBE_FORMAT);
    printf("mupdf %s\n", FZ_VERSION);
    printf("document %s\n", basename_portable(path));
    printf("mode %s\n", mode);

    doc = spdf_open(path, err, sizeof(err));
    if (!doc) {
        /* err text comes from MuPDF and may mention a host path, so it goes to
         * stderr -- out of the diffed stream -- while stdout stays comparable. */
        printf("open FAILED\n");
        fprintf(stderr, "probe: open failed: %s\n", err);
        return 1;
    }

    pages = spdf_page_count(doc);
    printf("pages %d\n", pages);
    if (pages <= 0) {
        fprintf(stderr, "probe: document reports %d pages\n", pages);
        spdf_close(doc);
        return 1;
    }

    for (i = 0; i < pages && i < MAX_PAGES_LISTED; ++i) {
        float w = 0.0f, h = 0.0f;
        if (!spdf_page_size(doc, i, &w, &h, err, sizeof(err))) {
            printf("page %d size FAILED\n", i);
            fprintf(stderr, "probe: page %d size failed: %s\n", i, err);
            spdf_close(doc);
            return 1;
        }
        printf("page %d size %.4f x %.4f\n", i, (double)w, (double)h);
    }
    if (pages > MAX_PAGES_LISTED) printf("page ... %d more not listed\n", pages - MAX_PAGES_LISTED);

    if (page < 0 || page >= pages) {
        fprintf(stderr, "probe: page %d out of range (0..%d)\n", page, pages - 1);
        spdf_close(doc);
        return 2;
    }

    memset(&bitmap, 0, sizeof(bitmap));
    if (!spdf_render_page_rgba_opts(doc, page, (float)zoom, flags, NULL, &bitmap, err, sizeof(err))) {
        printf("render FAILED\n");
        fprintf(stderr, "probe: render failed: %s\n", err);
        spdf_close(doc);
        return 1;
    }

    printf("render page %d zoom %.4f -> %d x %d\n", page, zoom, bitmap.width, bitmap.height);
    /* Stride is a legitimate per-host implementation choice, so it is reported
     * as a derived fact (padding present or not) rather than as a raw number
     * that would make an innocuous difference look like a failure. */
    printf("stride-padding %d\n", bitmap.stride - bitmap.width * 4);

    for (i = 0; i < bitmap.height; ++i) {
        const unsigned char* row = bitmap.rgba + (size_t)i * (size_t)bitmap.stride;
        int x;
        for (x = 0; x < bitmap.width; ++x) {
            const unsigned char* px = row + (size_t)x * 4;
            int a = px[3];
            sum_r += px[0];
            sum_g += px[1];
            sum_b += px[2];
            sum_a += a;
            if (a < amin) amin = a;
            if (a > amax) amax = a;
            if (a != 255) nonopaque++;
            if (a == 0 && (px[0] || px[1] || px[2])) transparent_colored++;
            if (a > 0 && a < 255) {
                partial++;
                /* In a PREMULTIPLIED buffer every channel is <= alpha. A buffer
                 * that never violates that over many partial pixels is almost
                 * certainly premultiplied, whatever it claims to be. Counting
                 * violations here means the probe transcript alone can tell the
                 * two conventions apart, without needing the PNG comparison. */
                if (px[0] > a || px[1] > a || px[2] > a) premul_violations++;
            }
        }
    }

    /* Integer means, truncated -- see the determinism rule at the top. */
    {
        unsigned long long n = (unsigned long long)bitmap.width * (unsigned long long)bitmap.height;
        printf("mean-rgba %lu %lu %lu %lu\n", (unsigned long)(sum_r / n), (unsigned long)(sum_g / n),
               (unsigned long)(sum_b / n), (unsigned long)(sum_a / n));
        printf("alpha-range %d %d\n", amin, amax);
        printf("alpha-nonopaque %lu\n", (unsigned long)nonopaque);
        printf("alpha-partial %lu\n", (unsigned long)partial);
        printf("alpha-transparent-colored %lu\n", (unsigned long)transparent_colored);
        printf("alpha-straight-evidence %lu\n", (unsigned long)premul_violations);
    }

    for (gy = 0; gy < GRID; ++gy) {
        for (gx = 0; gx < GRID; ++gx) {
            /* Integer pixel indices derived with integer arithmetic: (2i+1)*n/(2*GRID)
             * so no float rounding can put two hosts on neighbouring pixels. */
            int px_x = (2 * gx + 1) * bitmap.width / (2 * GRID);
            int px_y = (2 * gy + 1) * bitmap.height / (2 * GRID);
            const unsigned char* p = bitmap.rgba + (size_t)px_y * (size_t)bitmap.stride + (size_t)px_x * 4;
            printf("sample %d %d %02X%02X%02X%02X\n", gx, gy, p[0], p[1], p[2], p[3]);
        }
    }

    checksum_pixels(bitmap.rgba, bitmap.width, bitmap.height, bitmap.stride, digest, sizeof(digest));
    printf("checksum fnv1a64 %s\n", digest);

    if (png_path) {
        write_png(png_path, bitmap.rgba, bitmap.width, bitmap.height, bitmap.stride);
        printf("png %s\n", basename_portable(png_path));
    }

    printf("ok\n");
    spdf_free_bitmap(&bitmap);
    spdf_close(doc);
    return 0;
}
