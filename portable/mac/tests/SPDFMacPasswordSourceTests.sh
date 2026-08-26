#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
password_impl="$root/portable/mac/SPDFMacPassword.mm"
password_header="$root/portable/mac/SPDFMacPassword.h"
app_impl="$root/portable/mac/ShenzhenPDFMac.mm"
properties_impl="$root/portable/mac/SPDFMacPropertiesPanel.mm"
core_impl="$root/portable/core/shenzhen_pdf_core.c"
core_header="$root/portable/core/shenzhen_pdf_core.h"

grep -q 'NSSecureTextField' "$password_impl"
grep -q 'beginSheet:' "$password_impl"
if grep -q 'runModal' "$password_impl"; then
    echo "password prompt must remain asynchronous" >&2
    exit 1
fi
if grep -Eiq 'NSUserDefaults|settings\.json|session\.json|bookmarks\.json|NSLog|os_log' "$password_impl"; then
    echo "password implementation contains persistence or logging" >&2
    exit 1
fi
grep -q 'sourceIdentityTokenForSourcePath:' "$password_header"
grep -q 'sourceIdentityTokenForSourcePath:sourcePath' "$app_impl"
if grep -q 'cacheTokenForSourcePath:sourcePath.*sourceIdentity' "$app_impl"; then
    echo "password prompt file-race check must not use a credential/cache token" >&2
    exit 1
fi
python3 - "$password_impl" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
create = 'credential = [[SPDFPasswordCredential alloc] initWithPassword:_passwordField.stringValue];'
clear = '_passwordField.stringValue = @"";'
if create not in source or clear not in source or source.index(clear, source.index(create)) - source.index(create) > 180:
    raise SystemExit("secure password field is not cleared immediately after credential creation")
PY
if grep -n 'spdf_open(' "$app_impl" "$properties_impl"; then
    echo "macOS reopen path bypasses the credential-aware opener" >&2
    exit 1
fi
if [ "$(grep -c "spdf_has_permission(_doc, 'c')" "$app_impl")" -lt 8 ]; then
    echo "encrypted-PDF copy actions do not consistently enforce copy permission" >&2
    exit 1
fi
grep -q 'ensureContentCopyPermissionForOperation:@"Web search"' "$app_impl"
if [ "$(grep -c 'ensureContentCopyPermissionForOperation:@"Translation"' "$app_impl")" -lt 2 ]; then
    echo "selection and document translation must both enforce copy permission" >&2
    exit 1
fi
grep -q "allowed = doc->password_protected ? 0 : 1;" "$core_impl"
if grep -q 'spdf_save_decrypted_copy' "$core_impl" "$core_header" "$app_impl"; then
    echo "password support must not create plaintext decrypted copies" >&2
    exit 1
fi
grep -q 'OCR is unavailable for password-protected PDFs' "$app_impl"
grep -q '!spdf_is_password_protected(_doc) &&' "$app_impl"
grep -q "spdf_has_permission(_doc, 'h') ? 1200.0 : 150.0" "$app_impl"

echo "SPDF mac password source tests passed"
