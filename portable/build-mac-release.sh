#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Build a NON-sandboxed, notarized macOS .dmg for direct distribution
(your own website / GitHub releases) — outside the Mac App Store.

Unlike the TestFlight build, this is NOT sandboxed, so OCR (ocrmypdf), saving,
rotating, comments, and delete-text all work normally — the way the app behaves
when run locally.

Prerequisites (one-time):
  1. A "Developer ID Application" certificate in your keychain.
     Create it CSR-first: Keychain Access > Certificate Assistant > Request a
     Certificate from a Certificate Authority (Save to disk), then
     developer.apple.com > Certificates > + > Developer ID Application > upload
     the CSR > download and double-click the .cer.
     NOTE: Developer ID certs can usually only be created by the account HOLDER.
  2. A notarytool credential stored in your keychain:
     xcrun notarytool store-credentials <profile-name> \
       --apple-id <your-apple-id> --team-id <TEAMID> \
       --password <app-specific-password>     # from appleid.apple.com
  3. portable/.release.env filled in (copy .release.env.example).

Then just run:  ./portable/build-mac-release.sh
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# Load local, git-ignored signing config if present (see .release.env.example).
if [[ -f "$script_dir/.release.env" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$script_dir/.release.env"
fi

: "${MAC_VERSION:=26.6.19}"

need_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "$name is required." >&2
    echo >&2
    usage >&2
    exit 2
  fi
}

need_var MAC_SIGN_IDENTITY
need_var NOTARY_PROFILE

if [[ "$MAC_SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "MAC_SIGN_IDENTITY must be a 'Developer ID Application' certificate for a" >&2
  echo "directly-distributed (non-App-Store) build. Got: $MAC_SIGN_IDENTITY" >&2
  exit 2
fi

if ! security find-identity -v -p codesigning | grep -qF "$MAC_SIGN_IDENTITY"; then
  echo "Signing identity not found in your keychain:" >&2
  echo "  $MAC_SIGN_IDENTITY" >&2
  echo "Create a Developer ID Application certificate first (see --help)." >&2
  exit 2
fi

echo "Building + notarizing (this submits to Apple and waits; can take a few minutes)..."
make -C "$repo_root/portable" release-dmg \
  MAC_VERSION="$MAC_VERSION" \
  MAC_SIGN_IDENTITY="$MAC_SIGN_IDENTITY" \
  NOTARY_PROFILE="$NOTARY_PROFILE"

dmg="$repo_root/dist/ShenzhenPDF-mac-arm64.dmg"
echo
echo "Notarized, stapled DMG ready for direct distribution:"
echo "  $dmg"
