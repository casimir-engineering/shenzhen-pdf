/* password_test.c — spdf_win_open_document_interactive() against the real core,
 * on the paths that need no dialog.
 *
 * A dialog cannot be shown on a locked workstation (windows-native-observations
 * 4.6), so what is asserted here is everything AROUND it: a plain document
 * opens with ZERO prompts (the prompt counter exists for exactly this
 * assertion), a missing file is an error with the core's message and not a
 * cancellation, and the argument contract holds. The prompt loop itself is
 * pinned by password_flow_test.c; the core's own handling of the three
 * encrypted fixtures is SPDFCorePasswordTests, which qpdf now unblocks.
 */
/* spdf-test-sources: portable/win/src/spdf_win_password.cpp portable/win/src/spdf_win_paths.c portable/core/shenzhen_pdf_core.c portable/core/spdf_selection.c portable/core/spdf_selection_support.c portable/core/spdf_recolor.c portable/core/spdf_win_compat.c */
/* spdf-test-args: portable/win/tests/fixtures/outline.pdf */
/* spdf-test-needs: mupdf */
#include "spdf_win_password.h"

#include <stdio.h>
#include <string.h>

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

int main(int argc, char** argv) {
    spdf_document* doc = NULL;
    char err[256];
    const char* fixture = argc > 1 ? argv[1] : "portable/win/tests/fixtures/outline.pdf";

    /* A plain document: opened, no prompt. */
    err[0] = 'x';
    CHECK(spdf_win_open_document_interactive(NULL, fixture, &doc, err, sizeof(err)) == 1);
    CHECK(doc != NULL);
    CHECK(spdf_win_password_last_prompt_count() == 0);
    if (doc) {
        CHECK(spdf_page_count(doc) > 0);
        CHECK(!spdf_is_password_protected(doc));
        spdf_close(doc);
    }

    /* A missing file: an error, with a message, still no prompt. */
    doc = (spdf_document*)1;
    err[0] = 0;
    CHECK(spdf_win_open_document_interactive(NULL, "C:\\no\\such\\file-spdf.pdf", &doc, err, sizeof(err)) == -1);
    CHECK(doc == NULL);
    CHECK(err[0] != 0);
    CHECK(spdf_win_password_last_prompt_count() == 0);

    /* The argument contract. */
    CHECK(spdf_win_open_document_interactive(NULL, fixture, NULL, err, sizeof(err)) == -1);
    doc = (spdf_document*)1;
    CHECK(spdf_win_open_document_interactive(NULL, "", &doc, err, sizeof(err)) == -1);
    CHECK(doc == NULL);
    CHECK(strcmp(err, "No path was given.") == 0);
    CHECK(spdf_win_open_document_interactive(NULL, NULL, &doc, NULL, 0) == -1);

    printf("password_test: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures ? 1 : 0;
}
