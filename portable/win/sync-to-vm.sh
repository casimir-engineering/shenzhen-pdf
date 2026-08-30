#!/usr/bin/env bash
# Mirror the platform-independent parts of the repo into a directory the
# Parallels guest can actually see.
#
# WHY THIS EXISTS: the guest mounts the Mac home directory but only exposes
# Desktop, Documents and Downloads. ~/Projects is NOT shared, so the repo is
# invisible from Windows no matter how the path is spelled. We therefore stage
# a copy under ~/Documents, which the guest reads as
#   \\Mac\Home\Documents\spdf-win
# The mapped drive Z: that Parallels sets up for the interactive user does NOT
# exist in the SYSTEM session `prlctl exec` runs in, so guest-side tooling must
# use the UNC path, never Z:.
#
# Idempotent: rsync --delete makes the staging tree exactly match the repo, so
# a deleted source file disappears on the Windows side too.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE="${SPDF_WIN_STAGE:-$HOME/Documents/spdf-win}"

mkdir -p "$STAGE"

# Only the parts a Windows build can possibly need. portable/mac and
# portable/linux are deliberately absent: syncing them would just make the
# copy-into-guest step slower for files MSVC will never open.
SUBTREES=(portable/core portable/win ext)

RSYNC_ARGS=(
  -a --delete
  --exclude '.git'
  --exclude '.DS_Store'
  # Build output, ours and the guest's. build/ is where vm-build.sh drops both
  # the macOS reference binary and the fetched guest artifacts.
  --exclude 'build/'
  --exclude '*.o'
  --exclude '*.obj'
  --exclude '*.a'
  --exclude '*.lib'
  --exclude '*.pdb'
  --exclude '*.ilk'
  --exclude '*.exe'
)

for sub in "${SUBTREES[@]}"; do
  mkdir -p "$STAGE/$(dirname "$sub")"
  rsync "${RSYNC_ARGS[@]}" "$REPO_ROOT/$sub/" "$STAGE/$sub/"
done

if [[ "${SPDF_WIN_SYNC_QUIET:-0}" != "1" ]]; then
  printf 'staged %s -> %s (%s files, %s)\n' \
    "$(IFS=' '; echo "${SUBTREES[*]}")" \
    "$STAGE" \
    "$(find "$STAGE" -type f | wc -l | tr -d ' ')" \
    "$(du -sh "$STAGE" | cut -f1)"
  printf 'guest sees this as \\\\Mac\\Home\\Documents\\%s\n' "$(basename "$STAGE")"
fi
