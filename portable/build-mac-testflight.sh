#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Build a macOS TestFlight upload package.

Your Apple Developer account holder must create:
  1. An App Store Connect macOS app record.
  2. An explicit Bundle ID matching MAC_BUNDLE_ID.
  3. A Mac App Store distribution provisioning profile for that Bundle ID.
  4. An Apple Distribution signing certificate.
  5. A 3rd Party Mac Developer Installer certificate.

Example:
  MAC_BUNDLE_ID=com.intuition.shenzhenpdf \
  MAC_VERSION=26.6.19 \
  MAC_BUILD=1 \
  MAC_APPSTORE_IDENTITY="Apple Distribution: Friend Name (TEAMID1234)" \
  MAC_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Friend Name (TEAMID1234)" \
  MAC_PROVISIONING_PROFILE="$HOME/Downloads/ShenzhenPDF_AppStore.provisionprofile" \
  ./portable/build-mac-testflight.sh

Set OPEN_TRANSPORTER=1 to open the resulting .pkg in Apple's Transporter app.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# Load local, git-ignored signing identities/profile if present. Copy
# .testflight.env.example to .testflight.env and fill it in to run with no args.
if [[ -f "$script_dir/.testflight.env" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$script_dir/.testflight.env"
fi

: "${MAC_BUNDLE_ID:=com.intuition.shenzhenpdf}"
: "${MAC_VERSION:=26.6.19}"
: "${MAC_BUILD:=1}"
: "${OPEN_TRANSPORTER:=0}"

need_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "$name is required." >&2
    echo >&2
    usage >&2
    exit 2
  fi
}

need_var MAC_APPSTORE_IDENTITY
need_var MAC_INSTALLER_IDENTITY
need_var MAC_PROVISIONING_PROFILE

if [[ ! -f "$MAC_PROVISIONING_PROFILE" ]]; then
  echo "MAC_PROVISIONING_PROFILE does not exist: $MAC_PROVISIONING_PROFILE" >&2
  exit 2
fi

if ! command -v productbuild >/dev/null 2>&1; then
  echo "productbuild is required. Install Xcode first." >&2
  exit 2
fi

# The Mac App Store requires the app icon in a compiled asset catalog
# (Assets.car); without it the upload is rejected with error 90546. Only the
# full Xcode ships actool — Command Line Tools alone do not. Fail early rather
# than build a package that Transporter will reject.
if ! xcrun --find actool >/dev/null 2>&1; then
  echo "actool was not found, so the app icon asset catalog cannot be built." >&2
  echo "The App Store rejects packages without it (error 90546)." >&2
  echo "actool ships only with the full Xcode, not the Command Line Tools." >&2
  echo >&2
  echo "Install Xcode from the App Store, then either run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app" >&2
  echo "or prefix this command with:" >&2
  echo "  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" >&2
  exit 2
fi

make -C "$repo_root/portable" testflight-pkg \
  MAC_BUNDLE_ID="$MAC_BUNDLE_ID" \
  MAC_VERSION="$MAC_VERSION" \
  MAC_BUILD="$MAC_BUILD" \
  MAC_APPSTORE_IDENTITY="$MAC_APPSTORE_IDENTITY" \
  MAC_INSTALLER_IDENTITY="$MAC_INSTALLER_IDENTITY" \
  MAC_PROVISIONING_PROFILE="$MAC_PROVISIONING_PROFILE"

pkg="$repo_root/dist/ShenzhenPDF-testflight-$MAC_VERSION-$MAC_BUILD.pkg"
echo
echo "TestFlight package is ready:"
echo "  $pkg"

if [[ "$OPEN_TRANSPORTER" == "1" ]]; then
  if ! open -Ra Transporter >/dev/null 2>&1; then
    echo "Transporter is not installed. Install it from the Mac App Store, then drag the .pkg into it." >&2
    exit 2
  fi
  open -a Transporter "$pkg"
fi
