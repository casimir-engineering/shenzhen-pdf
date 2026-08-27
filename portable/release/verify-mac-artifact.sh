#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 [--unsigned] --dmg <path> --version <YY.M.DD> --build <n> --bundle-id <id> [--team-id <id>] --min-os <version>" >&2
  exit 2
}

unsigned=0
dmg=""
version=""
build=""
bundle_id=""
team_id=""
min_os=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned) unsigned=1; shift ;;
    --dmg) dmg="${2:-}"; shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    --build) build="${2:-}"; shift 2 ;;
    --bundle-id) bundle_id="${2:-}"; shift 2 ;;
    --team-id) team_id="${2:-}"; shift 2 ;;
    --min-os) min_os="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -f "$dmg" && -n "$version" && -n "$build" && -n "$bundle_id" && -n "$min_os" ]] || usage
[[ "$unsigned" == 1 || -n "$team_id" ]] || usage
[[ "$(basename "$dmg")" == "ShenzhenPDF-mac-arm64.dmg" ]] || {
  echo "Unexpected update asset name: $(basename "$dmg")" >&2
  exit 1
}

bytes="$(stat -f '%z' "$dmg")"
(( bytes < 64 * 1024 * 1024 )) || {
  echo "DMG is $bytes bytes; the updater requires less than 64 MiB." >&2
  exit 1
}

if [[ "$unsigned" == 0 ]]; then
  codesign --verify --strict --verbose=2 "$dmg"
  dmg_signing="$(codesign -d --verbose=4 "$dmg" 2>&1)"
  grep -Fq "TeamIdentifier=$team_id" <<<"$dmg_signing" || { echo "DMG Team ID mismatch." >&2; exit 1; }
  xcrun stapler validate "$dmg"
  spctl -a -vv -t open --context context:primary-signature "$dmg"
fi

mount_point="$(mktemp -d /tmp/spdf-release-verify.XXXXXX)"
cleanup() {
  hdiutil detach "$mount_point" >/dev/null 2>&1 || \
    hdiutil detach -force "$mount_point" >/dev/null 2>&1 || true
  rmdir "$mount_point" >/dev/null 2>&1 || true
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount_point" "$dmg" >/dev/null

shopt -s nullglob
all_apps=("$mount_point"/*.app)
apps=()
for candidate in "${all_apps[@]}"; do
  [[ -L "$candidate" ]] || apps+=("$candidate")
done
[[ ${#apps[@]} -eq 1 ]] || {
  echo "Expected exactly one non-symlink root app; found ${#apps[@]}." >&2
  exit 1
}
app="${apps[0]}"
plist="$app/Contents/Info.plist"
binary="$app/Contents/MacOS/ShenzhenPDF"

codesign --verify --deep --strict --verbose=2 "$app"
app_signing="$(codesign -d --verbose=4 "$app" 2>&1)"
if [[ "$unsigned" == 0 ]]; then
  grep -Fq "TeamIdentifier=$team_id" <<<"$app_signing" || { echo "App Team ID mismatch." >&2; exit 1; }
  grep -Eq 'flags=.*runtime' <<<"$app_signing" || { echo "Hardened runtime is missing." >&2; exit 1; }
  spctl -a -vv -t execute "$app"
fi

actual_bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
[[ "$actual_bundle" == "$bundle_id" ]] || { echo "Bundle ID mismatch: $actual_bundle" >&2; exit 1; }
[[ "$actual_version" == "$version" ]] || { echo "Version mismatch: $actual_version" >&2; exit 1; }
[[ "$actual_build" == "$build" ]] || { echo "Build mismatch: $actual_build" >&2; exit 1; }
[[ ! -e "$app/Contents/embedded.provisionprofile" ]] || { echo "A provisioning profile is embedded in the direct-download app." >&2; exit 1; }

mach_count=0
while IFS= read -r -d '' file_path; do
  file_description="$(file -b "$file_path")"
  [[ "$file_description" == *Mach-O* ]] || continue
  mach_count=$((mach_count + 1))
  archs="$(lipo -archs "$file_path")"
  [[ "$archs" == "arm64" ]] || { echo "Unexpected architectures in $file_path: $archs" >&2; exit 1; }
  object_min_os="$(vtool -show-build "$file_path" | awk '$1 == "minos" { print $2; exit }')"
  [[ "$object_min_os" == "$min_os" ]] || { echo "Unexpected minOS in $file_path: $object_min_os (expected $min_os)" >&2; exit 1; }
  if otool -L "$file_path" | grep -Eq 'libcrypto|/opt/homebrew|/usr/local'; then
    echo "Mutable or forbidden runtime dependency in $file_path:" >&2
    otool -L "$file_path" >&2
    exit 1
  fi
done < <(find "$app" -type f -print0)
(( mach_count > 0 )) || { echo "No Mach-O payload found in app." >&2; exit 1; }

entitlements="$(codesign -d --entitlements - "$app" 2>/dev/null || true)"
if grep -q 'com.apple.security.app-sandbox' <<<"$entitlements"; then
  echo "The direct-download app unexpectedly has the sandbox entitlement." >&2
  exit 1
fi

reported="$($binary --version)"
[[ "$reported" == *"$version-$build"* ]] || { echo "--version mismatch: $reported" >&2; exit 1; }

echo "Verified $(basename "$dmg"): $version-$build, arm64, minOS $min_os, $bytes bytes."
