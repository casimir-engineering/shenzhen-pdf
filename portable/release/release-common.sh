#!/usr/bin/env bash

# Public constants consumed by scripts that source this library.
# shellcheck disable=SC2034
SPDF_RELEASE_TEAM_ID="66LJ4BV7Q3"
# shellcheck disable=SC2034
SPDF_RELEASE_BUNDLE_ID="com.intuition.shenzhenpdf"
# shellcheck disable=SC2034
SPDF_RELEASE_ARCH="arm64"
# shellcheck disable=SC2034
SPDF_RELEASE_MIN_OS="12.0"
# shellcheck disable=SC2034
SPDF_RELEASE_OPTFLAGS="-O2 -DNDEBUG"
# shellcheck disable=SC2034
SPDF_RELEASE_GITHUB_REPOSITORY="casimir-engineering/shenzhen-pdf"
SPDF_RELEASE_ASSET_NAME="ShenzhenPDF-mac-arm64.dmg"

spdf_release_fail() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

spdf_read_make_var() {
  local file="$1"
  local name="$2"
  awk -v key="$name" '$1 == key && $2 == "?=" { print $3; exit }' "$file"
}

spdf_discover_test_targets() {
  local makefile="$1"
  sed -nE 's/^([A-Za-z0-9_-]+-tests):.*/\1/p' "$makefile" | sort -u
}

spdf_commit_for_ref() {
  local repo_root="$1"
  local ref="$2"
  git -C "$repo_root" rev-parse --verify "${ref}^{commit}" 2>/dev/null
}

spdf_remote_tag_commit() {
  local repo_root="$1"
  local remote="$2"
  local tag="$3"
  local refs peeled direct

  refs="$(git -C "$repo_root" ls-remote --tags "$remote" "refs/tags/$tag" "refs/tags/$tag^{}")"
  peeled="$(printf '%s\n' "$refs" | awk -v ref="refs/tags/$tag^{}" '$2 == ref { print $1; exit }')"
  direct="$(printf '%s\n' "$refs" | awk -v ref="refs/tags/$tag" '$2 == ref { print $1; exit }')"
  printf '%s\n' "${peeled:-$direct}"
}

spdf_require_ref_at_commit() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  [[ -z "$actual" || "$actual" == "$expected" ]] || \
    spdf_release_fail "$label points to $actual instead of prepared commit $expected"
}

spdf_ensure_local_tag() {
  local repo_root="$1"
  local tag="$2"
  local commit="$3"
  local existing

  existing="$(spdf_commit_for_ref "$repo_root" "refs/tags/$tag" || true)"
  spdf_require_ref_at_commit "Local tag $tag" "$existing" "$commit" || return 1
  if [[ -z "$existing" ]]; then
    git -C "$repo_root" tag "$tag" "$commit"
  fi
}

spdf_verify_published_asset() {
  local repository="$1"
  local tag="$2"
  local dmg="$3"
  local expected_name="$4"
  local tmp remote_dmg expected_hash actual_hash metadata

  metadata="$(gh api "repos/$repository/releases/tags/$tag" \
    --jq '[.tag_name, .draft, .prerelease, ([.assets[] | select(.name == "'"$expected_name"'")] | length)] | @tsv')"
  [[ "$metadata" == "$tag"$'\t'"false"$'\t'"false"$'\t'"1" ]] || \
    spdf_release_fail "GitHub release $tag is not a public final release with exactly one $expected_name asset" || return 1

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/spdf-release-asset.XXXXXX")"
  remote_dmg="$tmp/$expected_name"
  if ! gh release download "$tag" -R "$repository" --pattern "$expected_name" --dir "$tmp" --clobber; then
    rm -rf "$tmp"
    return 1
  fi
  [[ -f "$remote_dmg" ]] || {
    rm -rf "$tmp"
    spdf_release_fail "GitHub release download did not produce $expected_name"
    return 1
  }
  expected_hash="$(shasum -a 256 "$dmg" | awk '{print $1}')"
  actual_hash="$(shasum -a 256 "$remote_dmg" | awk '{print $1}')"
  rm -rf "$tmp"
  [[ "$actual_hash" == "$expected_hash" ]] || \
    spdf_release_fail "Published $expected_name hash $actual_hash != local release hash $expected_hash"
}

spdf_publish_github_release() {
  local repository="$1"
  local tag="$2"
  local notes="$3"
  local dmg="$4"
  local existing_state existing_tag existing_draft existing_prerelease

  existing_state="$(gh release view "$tag" -R "$repository" \
    --json tagName,isDraft,isPrerelease \
    --jq '[.tagName, .isDraft, .isPrerelease] | @tsv' 2>/dev/null || true)"
  if [[ -n "$existing_state" ]]; then
    IFS=$'\t' read -r existing_tag existing_draft existing_prerelease <<<"$existing_state"
    [[ "$existing_tag" == "$tag" ]] || \
      spdf_release_fail "GitHub returned release $existing_tag while publishing $tag" || return 1
    [[ "$existing_draft" == "true" || "$existing_draft" == "false" ]] || \
      spdf_release_fail "GitHub returned an invalid draft state for $tag" || return 1
    [[ "$existing_prerelease" == "true" || "$existing_prerelease" == "false" ]] || \
      spdf_release_fail "GitHub returned an invalid prerelease state for $tag" || return 1
    gh release edit "$tag" -R "$repository" --title "$tag" --notes-file "$notes" \
      --draft=false --prerelease=false --latest
    gh release upload "$tag" -R "$repository" "$dmg" --clobber
  else
    gh release create "$tag" -R "$repository" --title "$tag" --notes-file "$notes" \
      --draft=false --prerelease=false --latest "$dmg"
  fi
  spdf_verify_published_asset "$repository" "$tag" "$dmg" "$SPDF_RELEASE_ASSET_NAME"
}

spdf_validate_release_version() {
  local version="$1"
  [[ "$version" =~ ^[0-9]{2}\.[1-9][0-9]*\.[1-9][0-9]*$ ]] || \
    spdf_release_fail "Version must be an unpadded YY.M.DD value: $version"
}

spdf_next_build_for_tags() {
  local version="$1"
  local tags="$2"
  local escaped highest
  escaped="${version//./\\.}"
  highest="$(printf '%s\n' "$tags" | sed -nE "s/^${escaped}-([0-9]+)$/\\1/p" | sort -n | tail -1)"
  printf '%s\n' "$(( ${highest:-0} + 1 ))"
}

spdf_validate_release_notes() {
  local notes="$1"
  local divider_count highlights details chars

  [[ -f "$notes" ]] || spdf_release_fail "Release notes are missing: $notes" || return 1
  divider_count="$(grep -c '^---$' "$notes" || true)"
  [[ "$divider_count" == "1" ]] || spdf_release_fail "Release notes must contain exactly one standalone --- divider." || return 1

  highlights="$(sed '/^---$/q' "$notes" | sed '$d')"
  details="$(sed '1,/^---$/d' "$notes")"
  [[ -n "$(printf '%s' "$highlights" | tr -d '[:space:]')" ]] || spdf_release_fail "Release-note highlights are empty." || return 1
  [[ -n "$(printf '%s' "$details" | tr -d '[:space:]')" ]] || spdf_release_fail "Detailed release notes are empty." || return 1
  if printf '%s\n%s\n' "$highlights" "$details" | grep -Eiq 'EDIT ME|Nothing yet|(^|[^A-Za-z])(TBD|TODO)([^A-Za-z]|$)'; then
    spdf_release_fail "Release notes still contain a placeholder."
    return 1
  fi
  if ! printf '%s\n' "$highlights" | awk 'NF && $0 !~ /^- / { exit 1 }'; then
    spdf_release_fail "Every non-empty highlight line must start with '- '."
    return 1
  fi

  chars="$(printf '%s' "$highlights" | wc -m | tr -d ' ')"
  (( chars <= 500 )) || spdf_release_fail "Release-note highlights are ${chars} characters; the updater limit is 500." || return 1
  printf 'Release notes: %s highlight characters, strict format OK.\n' "$chars"
}

spdf_load_committed_release_metadata() {
  local repo_root="$1"
  local makefile="$repo_root/portable/Makefile"
  local plist="$repo_root/portable/mac/Info.plist"
  local mac_source="$repo_root/portable/mac/ShenzhenPDFMac.mm"
  local linux_header="$repo_root/portable/linux/gtk4/spdf_app.h"
  local readme="$repo_root/readme.md"
  local next_notes="$repo_root/portable/docs/release-notes-next.md"
  local plist_version plist_build

  SPDF_RELEASE_VERSION="$(spdf_read_make_var "$makefile" MAC_VERSION)"
  SPDF_RELEASE_BUILD="$(spdf_read_make_var "$makefile" MAC_BUILD)"
  spdf_validate_release_version "$SPDF_RELEASE_VERSION" || return 1
  [[ "$SPDF_RELEASE_BUILD" =~ ^[1-9][0-9]*$ ]] || spdf_release_fail "Invalid MAC_BUILD: $SPDF_RELEASE_BUILD" || return 1
  SPDF_RELEASE_TAG="$SPDF_RELEASE_VERSION-$SPDF_RELEASE_BUILD"
  SPDF_RELEASE_NOTES="$repo_root/portable/docs/releases/$SPDF_RELEASE_TAG.md"
  git -C "$repo_root" ls-files --error-unmatch -- "portable/docs/releases/$SPDF_RELEASE_TAG.md" >/dev/null 2>&1 || spdf_release_fail "Release notes are not tracked: $SPDF_RELEASE_NOTES" || return 1

  plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  plist_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
  [[ "$plist_version" == "$SPDF_RELEASE_VERSION" ]] || spdf_release_fail "Info.plist version $plist_version != $SPDF_RELEASE_VERSION" || return 1
  [[ "$plist_build" == "$SPDF_RELEASE_BUILD" ]] || spdf_release_fail "Info.plist build $plist_build != $SPDF_RELEASE_BUILD" || return 1
  grep -Fq "if (version.length == 0) version = @\"$SPDF_RELEASE_VERSION\";" "$mac_source" || spdf_release_fail "Mac display-version fallback is stale." || return 1
  grep -Fq "if (build.length == 0) build = @\"$SPDF_RELEASE_BUILD\";" "$mac_source" || spdf_release_fail "Mac display-build fallback is stale." || return 1
  grep -Fq "#define SPDF_APP_VERSION \"$SPDF_RELEASE_VERSION\"" "$linux_header" || spdf_release_fail "Linux release version is stale." || return 1
  grep -Fq "#define SPDF_APP_BUILD \"$SPDF_RELEASE_BUILD\"" "$linux_header" || spdf_release_fail "Linux release build is stale." || return 1
  grep -Fq "<sub>Latest <b>$SPDF_RELEASE_TAG</b>" "$readme" || spdf_release_fail "README release badge is stale." || return 1
  grep -Fq "since the last release ($SPDF_RELEASE_VERSION build $SPDF_RELEASE_BUILD)" "$next_notes" || spdf_release_fail "release-notes-next.md header is stale." || return 1
  spdf_validate_release_notes "$SPDF_RELEASE_NOTES" || return 1

  export SPDF_RELEASE_VERSION SPDF_RELEASE_BUILD SPDF_RELEASE_TAG SPDF_RELEASE_NOTES
}
