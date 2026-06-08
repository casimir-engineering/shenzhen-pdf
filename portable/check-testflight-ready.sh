#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

ok=0
warn=0
fail=0

pass() { echo "  OK   $1"; ok=$((ok + 1)); }
note() { echo "  WARN $1"; warn=$((warn + 1)); }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

echo "Shenzhen PDF — TestFlight readiness check"
echo "Repository: $repo_root"
echo

echo "Build tools"
if xcrun --find clang >/dev/null 2>&1; then pass "clang"; else bad "clang missing (install Xcode)"; fi
if xcrun --find productbuild >/dev/null 2>&1; then pass "productbuild"; else bad "productbuild missing (install Xcode)"; fi
if xcrun --find codesign >/dev/null 2>&1; then pass "codesign"; else bad "codesign missing"; fi
if command -v pkg-config >/dev/null 2>&1; then pass "pkg-config"; else bad "pkg-config missing (brew install pkg-config)"; fi
if pkg-config --exists openssl 2>/dev/null; then pass "OpenSSL ($(pkg-config --modversion openssl))"; else bad "OpenSSL missing (brew install openssl@3)"; fi
echo

echo "Apple signing identities"
appstore_id="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Distribution/ { print $2; exit }' || true)"
installer_id="$(security find-identity -v 2>/dev/null | awk -F'"' '/3rd Party Mac Developer Installer/ { print $2; exit }' || true)"
if [[ -n "$appstore_id" ]]; then
  pass "Apple Distribution: $appstore_id"
else
  bad "Apple Distribution certificate missing"
fi
if [[ -n "$installer_id" ]]; then
  pass "Installer certificate: $installer_id"
else
  bad "3rd Party Mac Developer Installer certificate missing"
fi
echo

echo "Provisioning profile"
profile="${MAC_PROVISIONING_PROFILE:-$HOME/Downloads/ShenzhenPDF_AppStore.provisionprofile}"
if [[ -f "$profile" ]]; then
  pass "Profile found: $profile"
  if command -v security >/dev/null 2>&1; then
    profile_bundle="$(security cms -D -i "$profile" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null || true)"
    if [[ -n "$profile_bundle" ]]; then
      echo "       application-identifier: $profile_bundle"
    fi
  fi
else
  bad "Profile missing: $profile"
  note "Download a Mac App Store Connect profile from developer.apple.com"
fi
echo

echo "Upload"
if open -Ra Transporter >/dev/null 2>&1; then pass "Transporter installed"; else note "Transporter not installed (Mac App Store)"; fi
echo

echo "MuPDF libraries"
if [[ -f "$repo_root/mupdf/build/release/libmupdf.a" ]]; then
  pass "libmupdf.a built"
else
  note "libmupdf.a not built yet (first build will compile MuPDF)"
fi
echo

echo "Suggested build command"
bundle_id="${MAC_BUNDLE_ID:-com.intuition.shenzhenpdf}"
version="${MAC_VERSION:-26.6.8}"
build=""
if [[ -n "$appstore_id" && -n "$installer_id" && -f "$profile" ]]; then
  cat <<EOF

MAC_BUNDLE_ID=$bundle_id \\
MAC_VERSION=$version \\
MAC_BUILD=$build \\
MAC_APPSTORE_IDENTITY="$appstore_id" \\
MAC_INSTALLER_IDENTITY="$installer_id" \\
MAC_PROVISIONING_PROFILE="$profile" \\
OPEN_TRANSPORTER=1 \\
./portable/build-mac-testflight.sh

EOF
else
  echo "  Complete the FAIL items above, then rerun this script."
fi

echo "Summary: $ok ok, $warn warnings, $fail failures"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
