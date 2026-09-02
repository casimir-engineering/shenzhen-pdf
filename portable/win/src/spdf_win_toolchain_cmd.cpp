/* spdf_win_toolchain_cmd.cpp -- the command lines the installer and the jobs
 * run, and the parsers for what comes back: argument quoting per
 * CommandLineToArgvW, the winget / pip / curl / certutil / argospm / NSIS
 * lines, the GitHub release JSON, SHA512SUMS and certutil digests, and the two
 * per-user directories. Pure strings; portable/win/tests/toolchain_test.c pins
 * every function. Split from spdf_win_toolchain.cpp at the 500-line cap. */
#include "spdf_win_toolchain.h"
#include "spdf_win_toolchain_internal.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

/* --- command lines ---------------------------------------------------------- */

size_t spdf_win_toolchain_quote_arg(const char* arg, char* out, size_t out_bytes) {
    size_t at = 0;
    int needs = !arg || !*arg;
    for (const char* p = arg ? arg : ""; *p && !needs; ++p)
        if (*p == ' ' || *p == '\t' || *p == '"') needs = 1;
    if (!needs) return put(out, out_bytes, 0, arg);
    at = put(out, out_bytes, at, "\"");
    {
        size_t backslashes = 0;
        for (const char* p = arg ? arg : ""; *p; ++p) {
            char one[2] = {*p, 0};
            if (*p == '\\') {
                ++backslashes;
                at = put(out, out_bytes, at, one);
                continue;
            }
            if (*p == '"') {
                /* CommandLineToArgvW: backslashes before a quote are doubled,
                 * then the quote itself is escaped. */
                for (size_t i = 0; i < backslashes + 1; ++i) at = put(out, out_bytes, at, "\\");
            }
            backslashes = 0;
            at = put(out, out_bytes, at, one);
        }
        for (size_t i = 0; i < backslashes; ++i) at = put(out, out_bytes, at, "\\");
    }
    return put(out, out_bytes, at, "\"");
}

size_t spdf_win_toolchain_join_argv(const char* const* argv, int argc, char* out, size_t out_bytes) {
    size_t at = 0;
    char q[SPDF_WIN_TC_CMD];
    for (int i = 0; i < argc; ++i) {
        if (i) at = put(out, out_bytes, at, " ");
        spdf_win_toolchain_quote_arg(argv[i], q, sizeof(q));
        at = put(out, out_bytes, at, q);
    }
    return at;
}

size_t spdf_win_toolchain_winget_cmd(const char* winget, const char* id, int user_scope, char* out, size_t out_bytes) {
    const char* argv[10] = {winget, "install", "--id", id, "-e", "--accept-source-agreements",
                            "--accept-package-agreements", "--disable-interactivity", "--scope", "user"};
    return spdf_win_toolchain_join_argv(argv, user_scope ? 10 : 8, out, out_bytes);
}

size_t spdf_win_toolchain_pip_cmd(const char* python, const char* const* packages, int count, char* out,
                                  size_t out_bytes) {
    const char* argv[16] = {python, "-m", "pip", "install", "--user", "--upgrade", "--progress-bar", "off"};
    int argc = 8;
    for (int i = 0; i < count && argc < 16; ++i) argv[argc++] = packages[i];
    return spdf_win_toolchain_join_argv(argv, argc, out, out_bytes);
}

size_t spdf_win_toolchain_curl_cmd(const char* curl, const char* url, const char* dest, char* out, size_t out_bytes) {
    const char* argv[7] = {curl, "-L", "-f", "-sS", "-o", dest, url};
    return spdf_win_toolchain_join_argv(argv, 7, out, out_bytes);
}

size_t spdf_win_toolchain_gs_installer_cmd(const char* installer, const char* dir, char* out, size_t out_bytes) {
    size_t at = spdf_win_toolchain_quote_arg(installer, out, out_bytes);
    at = put(out, out_bytes, at, " /S /D=");
    return put(out, out_bytes, at, dir); /* NSIS reads /D= to the end of the line, unquoted */
}

size_t spdf_win_toolchain_certutil_cmd(const char* certutil, const char* file, char* out, size_t out_bytes) {
    const char* argv[4] = {certutil, "-hashfile", file, "SHA512"};
    return spdf_win_toolchain_join_argv(argv, 4, out, out_bytes);
}

size_t spdf_win_toolchain_argospm_cmd(const char* argospm, const char* from_lang, const char* to_lang, char* out,
                                      size_t out_bytes) {
    char package[96];
    const char* argv[3] = {argospm, "install", package};
    if (!spdf_win_toolchain_argos_package_name(from_lang, to_lang, package, sizeof(package))) return 0;
    return spdf_win_toolchain_join_argv(argv, 3, out, out_bytes);
}

int spdf_win_toolchain_gs_asset_url(const char* release_json, char* out, size_t out_bytes) {
    const char* p = release_json ? release_json : "";
    static const char key[] = "\"browser_download_url\"";
    while ((p = strstr(p, key)) != NULL) {
        const char* q = strchr(p + sizeof(key) - 1, '"');
        const char* e = q ? strchr(q + 1, '"') : NULL;
        if (!q || !e) return 0;
        {
            size_t n = (size_t)(e - q - 1);
            const char* slash = e;
            while (slash > q && slash[-1] != '/') --slash;
            /* gs<digits>w64.exe: the 64-bit Windows installer and nothing else. */
            if (e - slash > 8 && strncmp(slash, "gs", 2) == 0 && strncmp(e - 7, "w64.exe", 7) == 0 &&
                n + 1 <= out_bytes) {
                int digits = 1;
                for (const char* d = slash + 2; d < e - 7; ++d)
                    if (!isdigit((unsigned char)*d)) digits = 0;
                if (digits) {
                    memcpy(out, q + 1, n);
                    out[n] = '\0';
                    return 1;
                }
            }
        }
        p = e;
    }
    return 0;
}

int spdf_win_toolchain_gs_sums_url(const char* asset_url, char* out, size_t out_bytes) {
    const char* slash = asset_url ? strrchr(asset_url, '/') : NULL;
    size_t n;
    if (!slash) return 0;
    n = (size_t)(slash - asset_url + 1);
    if (n + sizeof("SHA512SUMS") > out_bytes) return 0;
    memcpy(out, asset_url, n);
    strcpy(out + n, "SHA512SUMS");
    return 1;
}

int spdf_win_toolchain_sums_lookup(const char* sums_text, const char* file_name, char* hex_out, size_t out_bytes) {
    const char* p = sums_text ? sums_text : "";
    size_t want = file_name ? strlen(file_name) : 0;
    while (*p && want) {
        const char* e = strchr(p, '\n');
        size_t n = e ? (size_t)(e - p) : strlen(p);
        const char* name = p + n;
        while (name > p && name[-1] != ' ' && name[-1] != '\t' && name[-1] != '*' && name[-1] != '\r') --name;
        if ((size_t)(p + n - name) >= want && strncmp(name, file_name, want) == 0 &&
            (name[want] == '\r' || name[want] == '\0' || name[want] == '\n')) {
            size_t hex = 0;
            while (hex < n && isxdigit((unsigned char)p[hex])) ++hex;
            if (hex == 128 && out_bytes > 128) {
                for (size_t i = 0; i < 128; ++i) hex_out[i] = (char)tolower((unsigned char)p[i]);
                hex_out[128] = '\0';
                return 1;
            }
        }
        if (!e) break;
        p = e + 1;
    }
    return 0;
}

int spdf_win_toolchain_certutil_digest(const char* output, char* hex_out, size_t out_bytes) {
    const char* p = output ? output : "";
    while (*p) {
        const char* e = strchr(p, '\n');
        size_t n = e ? (size_t)(e - p) : strlen(p), got = 0;
        for (size_t i = 0; i < n && got <= 128; ++i) {
            if (isxdigit((unsigned char)p[i])) {
                if (got < 128 && out_bytes > 128) hex_out[got] = (char)tolower((unsigned char)p[i]);
                ++got;
            } else if (p[i] != ' ' && p[i] != '\r') {
                got = 0;
                break;
            }
        }
        if (got == 128 && out_bytes > 128) {
            hex_out[128] = '\0';
            return 1;
        }
        if (!e) break;
        p = e + 1;
    }
    return 0;
}

int spdf_win_toolchain_gs_install_dir(const SpdfWinToolchainRoots* roots, char* out, size_t out_bytes) {
    return roots && out && join2(out, out_bytes, roots->local_appdata, "Programs\\gs");
}

int spdf_win_toolchain_tessdata_parent(const SpdfWinToolchainRoots* roots, char* out, size_t out_bytes) {
    return roots && out && join2(out, out_bytes, roots->local_appdata, "ShenzhenPDF\\tesseract");
}

