#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Cut and publish a public ShenzhenPDF release in one command.

Usage:  ./portable/cut-release.sh [--dry-run] ["short summary for the commit"]

What it does, in order (failing fast and loudly at each step):
  1.  Derives the version from today's date (YY.M.DD, unpadded, e.g. 26.7.17)
      and auto-picks the build number: 1, or highest same-day tag + 1.
  2.  Verifies: on master, clean tree, gh authenticated, Developer ID signing
      identity in the keychain, notary keychain profile working.
  3.  Requires the release notes file  dist/release-notes-<ver>-<build>.md.
      If it is missing, it is SEEDED from the "Next release" section of
      portable/docs/release-notes-next.md and the script stops so you can
      edit it — write the highlights, then re-run.
  4.  Bumps the version in the five known locations (Makefile, Info.plist,
      ShenzhenPDFMac.mm displayVersion fallback, readme.md badge,
      release-notes-next.md header) and clears the "Next release" section.
      Each edit is grep-verified.
  5.  Runs every *-tests target discovered in portable/Makefile.
  6.  Commits "Release <ver> (build <n>): <summary>".
  7.  make release-dmg (sign -> notarize -> staple -> verify-mac-release),
      then checks the built app's --version output.
  8.  Tags <ver>-<build>, pushes master + tag, publishes the GitHub release
      (title = tag, notes file as body, DMG asset, marked latest), and
      confirms the /releases/latest/download/ URL resolves.

--dry-run runs the checks and the test suite, prints what every remaining
step WOULD do, and stops before modifying files, committing, tagging,
pushing, or publishing.

Release notes convention (dist/release-notes-<ver>-<build>.md):
  - A short highlights section at the TOP: punchy one-line markdown bullets.
  - A line containing only `---`, then the full detailed notes.
  - The in-app update alert shows ONLY the section above the first `---`,
    rendered as plain text with bullets, CAPPED AT 500 CHARACTERS — keep the
    highlights under that or they will be truncated with an ellipsis.

Prerequisites: see build-mac-release.sh (Developer ID certificate, notary
profile, portable/.release.env with MAC_SIGN_IDENTITY and NOTARY_PROFILE).
USAGE
}

log()  { printf '==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

DRY_RUN=0
SUMMARY=""
for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    -*) fail "Unknown option: $arg (see --help)" ;;
    *) SUMMARY="$arg" ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

# ---------------------------------------------------------------------------
# 1. Version + build number from today's date and existing tags
# ---------------------------------------------------------------------------
VERSION="$((10#$(date +%y))).$((10#$(date +%m))).$((10#$(date +%d)))"
BUILD=1
existing_tags="$(git tag --list "${VERSION}-*")"
if [[ -n "$existing_tags" ]]; then
  highest="$(printf '%s\n' "$existing_tags" | sed "s/^${VERSION}-//" | sort -n | tail -1)"
  BUILD=$((highest + 1))
  log "Version $VERSION build $highest already tagged -> next is build $BUILD"
fi
TAG="${VERSION}-${BUILD}"
NOTES_FILE="$repo_root/dist/release-notes-${TAG}.md"
DMG="$repo_root/dist/ShenzhenPDF-mac-arm64.dmg"
log "Cutting release $VERSION (build $BUILD), tag $TAG$([[ $DRY_RUN == 1 ]] && echo ' [DRY RUN]')"

# ---------------------------------------------------------------------------
# 2. Environment checks
# ---------------------------------------------------------------------------
branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "master" ]] || fail "Must be on master (currently on $branch)."
[[ -z "$(git status --porcelain)" ]] || fail "Working tree is not clean. Commit or stash first."
log "On master, working tree clean."

gh auth status >/dev/null 2>&1 || fail "gh is not authenticated. Run: gh auth login"
log "gh authenticated."

if [[ -f "$script_dir/.release.env" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$script_dir/.release.env"
fi
[[ -n "${MAC_SIGN_IDENTITY:-}" ]] || fail "MAC_SIGN_IDENTITY is not set (see portable/.release.env.example)."
[[ -n "${NOTARY_PROFILE:-}" ]] || fail "NOTARY_PROFILE is not set (see portable/.release.env.example)."
security find-identity -v -p codesigning | grep -qF "$MAC_SIGN_IDENTITY" \
  || fail "Signing identity not found in keychain: $MAC_SIGN_IDENTITY"
log "Signing identity present: $MAC_SIGN_IDENTITY"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "Notary profile '$NOTARY_PROFILE' did not work (xcrun notarytool history failed)."
log "Notary profile '$NOTARY_PROFILE' works."

# ---------------------------------------------------------------------------
# 3. Release notes file (seed from release-notes-next.md when missing)
# ---------------------------------------------------------------------------
NEXT_NOTES="$repo_root/portable/docs/release-notes-next.md"
if [[ ! -f "$NOTES_FILE" ]]; then
  if [[ $DRY_RUN == 1 ]]; then
    log "WARNING: notes file $NOTES_FILE is missing."
    log "         A real run would seed it from $NEXT_NOTES and stop for editing."
  else
    log "Notes file missing — seeding it from the 'Next release' section of release-notes-next.md."
    mkdir -p "$repo_root/dist"
    {
      echo "- EDIT ME: 5-8 punchy one-line highlight bullets (the in-app update"
      echo "- alert shows only this section, plain text, capped at 500 chars)"
      echo
      echo "---"
      echo
      # Everything after the "## Next release" heading.
      sed -n '/^## Next release$/,$p' "$NEXT_NOTES" | tail -n +2
    } > "$NOTES_FILE"
    fail "Seeded $NOTES_FILE — edit it (write the highlights above the ---), then re-run."
  fi
else
  log "Notes file found: $NOTES_FILE"
  highlights_chars="$(sed '/^---$/q' "$NOTES_FILE" | sed '$d' | tr '\n' ' ' | wc -c | tr -d ' ')"
  if (( highlights_chars > 500 )); then
    log "WARNING: highlights section is ~${highlights_chars} chars; the update alert caps at 500."
  else
    log "Highlights section ~${highlights_chars}/500 chars — fits the update alert."
  fi
fi

# ---------------------------------------------------------------------------
# 4. Test suite (all *-tests targets discovered from the Makefile)
# ---------------------------------------------------------------------------
test_targets="$(sed -nE 's/^([a-z-]+-tests):.*/\1/p' "$script_dir/Makefile" | sort -u | tr '\n' ' ')"
[[ -n "$test_targets" ]] || fail "No *-tests targets found in portable/Makefile."
log "Running test targets: $test_targets"
# shellcheck disable=SC2086
make -C "$script_dir" $test_targets
log "All tests passed."

# ---------------------------------------------------------------------------
# Dry run stops here
# ---------------------------------------------------------------------------
if [[ $DRY_RUN == 1 ]]; then
  cat <<EOF
==> DRY RUN complete. A real run would now:
    1. Bump the version to $VERSION build $BUILD in:
         portable/Makefile (MAC_VERSION / MAC_BUILD)
         portable/mac/Info.plist (CFBundleShortVersionString / CFBundleVersion)
         portable/mac/ShenzhenPDFMac.mm (displayVersion fallbacks)
         readme.md (download badge line)
         portable/docs/release-notes-next.md (header + clear 'Next release')
    2. Commit "Release $VERSION (build $BUILD): <summary>"
    3. make -C portable release-dmg (sign, notarize, staple, verify)
    4. Verify the built app prints $TAG from --version
    5. git tag $TAG && push master + tag
    6. gh release create $TAG --title $TAG --notes-file $NOTES_FILE --latest $DMG
    7. curl -I the /releases/latest/download/ URL to confirm it resolves
EOF
  exit 0
fi

if [[ -z "$SUMMARY" ]]; then
  read -r -p "Short summary for the release commit (Release $VERSION (build $BUILD): ...): " SUMMARY
  [[ -n "$SUMMARY" ]] || fail "A commit summary is required."
fi

# ---------------------------------------------------------------------------
# 5. Version bumps (grep-verified after each edit)
# ---------------------------------------------------------------------------
log "Bumping version to $VERSION build $BUILD."

sed -i '' -E "s/^MAC_VERSION \?= .*/MAC_VERSION ?= ${VERSION}/" "$script_dir/Makefile"
sed -i '' -E "s/^MAC_BUILD \?= .*/MAC_BUILD ?= ${BUILD}/" "$script_dir/Makefile"
grep -q "^MAC_VERSION ?= ${VERSION}$" "$script_dir/Makefile" || fail "Makefile MAC_VERSION bump failed."
grep -q "^MAC_BUILD ?= ${BUILD}$" "$script_dir/Makefile" || fail "Makefile MAC_BUILD bump failed."
log "  portable/Makefile OK"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$script_dir/mac/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD}" "$script_dir/mac/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$script_dir/mac/Info.plist")" == "$VERSION" ]] \
  || fail "Info.plist CFBundleShortVersionString bump failed."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$script_dir/mac/Info.plist")" == "$BUILD" ]] \
  || fail "Info.plist CFBundleVersion bump failed."
log "  portable/mac/Info.plist OK"

sed -i '' -E "s/if \(version\.length == 0\) version = @\"[^\"]*\";/if (version.length == 0) version = @\"${VERSION}\";/" \
  "$script_dir/mac/ShenzhenPDFMac.mm"
sed -i '' -E "s/if \(build\.length == 0\) build = @\"[^\"]*\";/if (build.length == 0) build = @\"${BUILD}\";/" \
  "$script_dir/mac/ShenzhenPDFMac.mm"
grep -q "version = @\"${VERSION}\";" "$script_dir/mac/ShenzhenPDFMac.mm" || fail "displayVersion fallback bump failed."
grep -q "build = @\"${BUILD}\";" "$script_dir/mac/ShenzhenPDFMac.mm" || fail "displayVersion build fallback bump failed."
log "  portable/mac/ShenzhenPDFMac.mm OK"

sed -i '' -E "s|<sub>Latest <b>[^<]*</b>|<sub>Latest <b>${TAG}</b>|" "$repo_root/readme.md"
grep -q "<sub>Latest <b>${TAG}</b>" "$repo_root/readme.md" || fail "readme.md badge bump failed."
log "  readme.md OK"

sed -i '' -E "s/^#define SPDF_APP_VERSION \".*\"/#define SPDF_APP_VERSION \"${VERSION}\"/" "$script_dir/linux/gtk4/spdf_app.h"
sed -i '' -E "s/^#define SPDF_APP_BUILD \".*\"/#define SPDF_APP_BUILD \"${BUILD}\"/" "$script_dir/linux/gtk4/spdf_app.h"
grep -q "#define SPDF_APP_VERSION \"${VERSION}\"" "$script_dir/linux/gtk4/spdf_app.h" || fail "spdf_app.h version bump failed."
grep -q "#define SPDF_APP_BUILD \"${BUILD}\"" "$script_dir/linux/gtk4/spdf_app.h" || fail "spdf_app.h build bump failed."
log "  portable/linux/gtk4/spdf_app.h OK"

{
  echo "# Release notes"
  echo
  echo "User-facing notes for changes merged since the last release (${VERSION} build ${BUILD})."
  echo "When cutting the next release, run ./portable/cut-release.sh — see \"Cutting a"
  echo "release\" below. The in-app updater shows the section above the first ---"
  echo "of the release body as plain text (500-char cap)."
  echo
  echo "## Cutting a release"
  echo
  echo "Run \`./portable/cut-release.sh [--dry-run] [\"commit summary\"]\`. It derives the"
  echo "date-based version, bumps it everywhere, runs all tests, builds + notarizes the"
  echo "DMG, tags, pushes, and publishes the GitHub release. Notes are read from"
  echo "\`dist/release-notes-<ver>-<build>.md\` (highlights above a --- divider, details"
  echo "below); if that file is missing the script seeds it from the section below and"
  echo "stops so you can edit it."
  echo
  echo "## Next release"
  echo
  echo "Nothing yet."
} > "$NEXT_NOTES"
grep -q "since the last release (${VERSION} build ${BUILD})" "$NEXT_NOTES" || fail "release-notes-next.md header bump failed."
log "  portable/docs/release-notes-next.md OK (Next release cleared)"

# ---------------------------------------------------------------------------
# 6. Commit
# ---------------------------------------------------------------------------
git add "$script_dir/Makefile" "$script_dir/mac/Info.plist" "$script_dir/mac/ShenzhenPDFMac.mm" \
        "$repo_root/readme.md" "$NEXT_NOTES"
git commit -m "Release ${VERSION} (build ${BUILD}): ${SUMMARY}"
log "Committed: $(git log -1 --format='%h %s')"

# ---------------------------------------------------------------------------
# 7. Build, sign, notarize, staple, verify
# ---------------------------------------------------------------------------
log "Building + notarizing (submits to Apple and waits; can take a few minutes)..."
make -C "$script_dir" release-dmg \
  MAC_VERSION="$VERSION" \
  MAC_BUILD="$BUILD" \
  MAC_SIGN_IDENTITY="$MAC_SIGN_IDENTITY" \
  NOTARY_PROFILE="$NOTARY_PROFILE"

reported="$("$repo_root/dist/ShenzhenPDF.app/Contents/MacOS/ShenzhenPDF" --version)"
[[ "$reported" == *"$TAG"* ]] || fail "Built app reports '$reported', expected version $TAG."
log "Built app reports: $reported"

# ---------------------------------------------------------------------------
# 8. Tag, push, publish
# ---------------------------------------------------------------------------
git tag "$TAG"
git push origin master
git push origin "$TAG"
log "Pushed master and tag $TAG."

gh release create "$TAG" --title "$TAG" --notes-file "$NOTES_FILE" --latest "$DMG"
log "Release published."

latest_head="$(curl -sI "https://github.com/casimir-engineering/shenzhen-pdf/releases/latest/download/ShenzhenPDF-mac-arm64.dmg")"
echo "$latest_head" | grep -qi "location: .*${TAG}/ShenzhenPDF-mac-arm64.dmg" \
  || fail "/releases/latest/download/ does not resolve to $TAG yet — check the release on GitHub."
log "https://github.com/casimir-engineering/shenzhen-pdf/releases/latest/download/ShenzhenPDF-mac-arm64.dmg -> $TAG"

log "Done: https://github.com/casimir-engineering/shenzhen-pdf/releases/tag/$TAG"
log "NEXT: on the Linux release machine, run portable/linux/pkg/cut-linux-assets.sh $TAG"
log "      to build, minisign-sign and upload the Linux deb + tarball (in-app"
log "      updater on Linux only offers releases that ship those assets)."
