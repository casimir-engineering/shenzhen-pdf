/* spdf_win_toolchain_plan.cpp -- the install plans: what a machine lacks for
 * OCR (Tesseract, Ghostscript, Python, ocrmypdf, language data) or for
 * translation (Python, argostranslate, a language package), as an ordered list
 * of steps the panel runs with a live log. Pure; the steps' command lines come
 * from spdf_win_toolchain_cmd.cpp and the probe results from the caller.
 * Split from spdf_win_toolchain.cpp at the 500-line cap. */
#include "spdf_win_toolchain.h"
#include "spdf_win_toolchain_internal.h"

#include <stdio.h>
#include <string.h>

/* --- plans -------------------------------------------------------------------- */

int spdf_win_toolchain_has(const SpdfWinToolchainState* st, spdf_win_tool tool) {
    return st && tool >= 0 && tool < SPDF_WIN_TOOL_COUNT && st->path[tool][0] != '\0';
}

static SpdfWinToolchainStep* plan_add(SpdfWinToolchainPlan* plan, int kind, const char* label) {
    SpdfWinToolchainStep* s;
    if (plan->count >= SPDF_WIN_TC_MAX_STEPS) return NULL;
    s = &plan->steps[plan->count++];
    memset(s, 0, sizeof(*s));
    s->kind = kind;
    snprintf(s->label, sizeof(s->label), "%s", label);
    return s;
}

static void plan_winget(SpdfWinToolchainPlan* plan, const SpdfWinToolchainState* st, const char* id, int user_scope,
                        const char* label, const char* fallback) {
    SpdfWinToolchainStep* s;
    if (!spdf_win_toolchain_has(st, SPDF_WIN_TOOL_WINGET)) {
        plan_add(plan, SPDF_WIN_TC_STEP_BLOCKED, fallback);
        return;
    }
    s = plan_add(plan, SPDF_WIN_TC_STEP_WINGET, label);
    if (!s) return;
    spdf_win_toolchain_winget_cmd(st->path[SPDF_WIN_TOOL_WINGET], id, user_scope, s->command, sizeof(s->command));
    if (!user_scope) plan->needs_elevation_note = 1;
}

static void plan_pip(SpdfWinToolchainPlan* plan, const SpdfWinToolchainState* st, const char* package,
                     const char* label) {
    const char* python = spdf_win_toolchain_has(st, SPDF_WIN_TOOL_PYTHON) ? st->path[SPDF_WIN_TOOL_PYTHON] : "python";
    SpdfWinToolchainStep* s = plan_add(plan, SPDF_WIN_TC_STEP_PIP, label);
    if (s) spdf_win_toolchain_pip_cmd(python, &package, 1, s->command, sizeof(s->command));
}

static void plan_python(SpdfWinToolchainPlan* plan, const SpdfWinToolchainState* st) {
    if (spdf_win_toolchain_has(st, SPDF_WIN_TOOL_PYTHON)) return;
    plan_winget(plan, st, SPDF_WIN_TC_WINGET_PYTHON, 1, "Installing Python 3.12 (winget, current user)",
                "Python is missing and winget is unavailable: install Python 3 from python.org or the Store");
}

void spdf_win_toolchain_ocr_plan(const SpdfWinToolchainState* st, const SpdfWinToolchainRoots* roots,
                                 const char* language, SpdfWinToolchainPlan* plan) {
    if (!plan) return;
    memset(plan, 0, sizeof(*plan));
    if (!st) return;
    if (!spdf_win_toolchain_has(st, SPDF_WIN_TOOL_TESSERACT))
        plan_winget(plan, st, SPDF_WIN_TC_WINGET_TESSERACT, 0, "Installing Tesseract OCR (winget)",
                    "Tesseract is missing and winget is unavailable: install UB-Mannheim Tesseract by hand");
    if (!spdf_win_toolchain_has(st, SPDF_WIN_TOOL_GHOSTSCRIPT)) {
        if (spdf_win_toolchain_has(st, SPDF_WIN_TOOL_CURL) && spdf_win_toolchain_has(st, SPDF_WIN_TOOL_CERTUTIL)) {
            SpdfWinToolchainStep* s = plan_add(plan, SPDF_WIN_TC_STEP_GHOSTSCRIPT,
                                               "Installing Ghostscript (official installer from GitHub, verified)");
            if (s && roots) spdf_win_toolchain_gs_install_dir(roots, s->dest, sizeof(s->dest));
            plan->needs_elevation_note = 1;
        } else {
            plan_add(plan, SPDF_WIN_TC_STEP_BLOCKED,
                     "Ghostscript is missing and curl.exe/certutil.exe are unavailable: install it from ghostscript.com");
        }
    }
    plan_python(plan, st);
    if (!spdf_win_toolchain_has(st, SPDF_WIN_TOOL_OCRMYPDF)) plan_pip(plan, st, "ocrmypdf", "Installing OCRmyPDF (pip --user)");
    for (int i = 0; i < st->missing_language_count && i < 8; ++i) {
        char parent[SPDF_WIN_TC_PATH], dir[SPDF_WIN_TC_PATH], leaf[64], url[256], label[160];
        SpdfWinToolchainStep* s;
        if (!roots || !spdf_win_toolchain_tessdata_parent(roots, parent, sizeof(parent)) ||
            !join2(dir, sizeof(dir), parent, "tessdata"))
            continue;
        if (!spdf_win_toolchain_has(st, SPDF_WIN_TOOL_CURL)) {
            snprintf(label, sizeof(label), "Language data %s is missing and curl.exe is unavailable",
                     st->missing_languages[i]);
            plan_add(plan, SPDF_WIN_TC_STEP_BLOCKED, label);
            continue;
        }
        snprintf(leaf, sizeof(leaf), "%s.traineddata", st->missing_languages[i]);
        snprintf(url, sizeof(url), "%s%s", SPDF_WIN_TC_TESSDATA_URL, leaf);
        snprintf(label, sizeof(label), "Downloading %s language data (tessdata_fast)", st->missing_languages[i]);
        s = plan_add(plan, SPDF_WIN_TC_STEP_TRAINEDDATA, label);
        if (!s || !join2(s->dest, sizeof(s->dest), dir, leaf)) continue;
        spdf_win_toolchain_curl_cmd(st->path[SPDF_WIN_TOOL_CURL], url, s->dest, s->command, sizeof(s->command));
    }
    (void)language;
}

void spdf_win_toolchain_argos_plan(const SpdfWinToolchainState* st, const char* from_lang, const char* to_lang,
                                   int with_package, SpdfWinToolchainPlan* plan) {
    if (!plan) return;
    memset(plan, 0, sizeof(*plan));
    if (!st) return;
    plan_python(plan, st);
    if (!spdf_win_toolchain_has(st, SPDF_WIN_TOOL_ARGOS_TRANSLATE) || !spdf_win_toolchain_has(st, SPDF_WIN_TOOL_ARGOSPM))
        plan_pip(plan, st, "argostranslate", "Installing Argos Translate (pip --user; pulls torch and ctranslate2)");
    if (with_package) {
        char label[160];
        const char* argospm =
            spdf_win_toolchain_has(st, SPDF_WIN_TOOL_ARGOSPM) ? st->path[SPDF_WIN_TOOL_ARGOSPM] : "argospm";
        SpdfWinToolchainStep* s;
        snprintf(label, sizeof(label), "Installing the %s to %s language package (argospm)", from_lang ? from_lang : "?",
                 to_lang ? to_lang : "?");
        s = plan_add(plan, SPDF_WIN_TC_STEP_ARGOSPM, label);
        if (s) spdf_win_toolchain_argospm_cmd(argospm, from_lang, to_lang, s->command, sizeof(s->command));
    }
}

