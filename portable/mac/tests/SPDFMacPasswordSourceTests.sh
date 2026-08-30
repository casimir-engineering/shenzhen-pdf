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
# Copy Page / Copy Page Image enablement and action bodies moved to the shared
# file-actions module; count enforcement across both homes so a refactor cannot
# silently drop a check.
file_actions_impl="$root/portable/mac/SPDFMacMarkdownFileActions.mm"
translation_impl="$root/portable/mac/SPDFMacTranslationEnablement.mm"
translation_policy="$root/portable/mac/SPDFMacTranslationPolicy.mm"
# Copy permission is enforced across the coordinator, the copy-page file
# actions and the translation context. Count the total rather than a
# per-file quota so consolidating duplicate checks into one shared context
# cannot trip the guard, while deleting a check still does.
permission_total=0
for impl in "$app_impl" "$file_actions_impl" "$translation_impl"; do
    permission_total=$((permission_total + $(grep -c "spdf_has_permission(_doc, 'c')" "$impl")))
done
if [ "$permission_total" -lt 10 ]; then
    echo "encrypted-PDF copy actions do not consistently enforce copy permission" >&2
    exit 1
fi
# Translation reads the permission through the shared context, and the policy
# must keep gating selection translation on it.
grep -q "context.contentCopyAllowed = context.markdownActive || (_doc && spdf_has_permission(_doc, 'c'))" \
    "$translation_impl" || {
    echo "translation context must derive copy permission from the open PDF" >&2
    exit 1
}
grep -q "!context.contentCopyAllowed" "$translation_policy" || {
    echo "selection translation must stay gated on copy permission" >&2
    exit 1
}
if [ "$(grep -c "spdf_has_permission(_doc, 'c')" "$file_actions_impl")" -lt 4 ]; then
    echo "copy-page file actions must enforce copy permission in enablement and action bodies" >&2
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
