#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/release-common.sh"

failures=0
expect_equal() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL %s: expected %s, got %s\n' "$label" "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}

expect_rejected() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL %s: input was accepted\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

spdf_validate_release_version "26.8.27"
expect_rejected "zero-padded month" spdf_validate_release_version "26.08.27"
expect_rejected "missing date field" spdf_validate_release_version "26.8"
expect_equal "multi-digit build selection" \
  "$(spdf_next_build_for_tags "26.8.27" $'26.8.27-2\n26.8.27-10\n26.8.26-99\n26.8.27-bad')" "11"
expect_equal "first build" "$(spdf_next_build_for_tags "26.8.27" "")" "1"

tmp="$(mktemp -d /tmp/spdf-release-common-tests.XXXXXX)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

printf '%s\n' '- Fast update' '' '---' '' 'Detailed change.' > "$tmp/valid.md"
spdf_validate_release_notes "$tmp/valid.md" >/dev/null
printf '%s\n' '- Fast update' '' '---' > "$tmp/no-details.md"
expect_rejected "empty details" spdf_validate_release_notes "$tmp/no-details.md"
printf '%s\n' '- TODO' '' '---' '' 'Detailed change.' > "$tmp/placeholder.md"
expect_rejected "placeholder" spdf_validate_release_notes "$tmp/placeholder.md"
printf '%s\n' 'not a bullet' '' '---' '' 'Detailed change.' > "$tmp/not-bullets.md"
expect_rejected "non-bullet highlights" spdf_validate_release_notes "$tmp/not-bullets.md"

if ((failures)); then
  printf 'release-common-tests: %d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'release-common-tests passed\n'
