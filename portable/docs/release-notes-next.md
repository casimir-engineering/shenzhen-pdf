# Release notes

User-facing notes for changes merged since the last release (26.10.7 build 2).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Dropping a tab between groups joins General. If General does not exist, it is
  created at the drop position; an existing General keeps its position and is
  revealed if hidden. This also works between collapsed groups and when moving
  a tab from another window. Membership and order persist across relaunches.
  Gap drops show an insertion marker and use the final mouse position, preventing
  a previously hovered group from capturing the drop.

- Missing originals remain readable from Collection in the same tab and group,
  with the same reading position. A red toolbar status and **Locate…** button
  offer automatic or manual recovery of the original.
- Collection documents are editable and renameable. Edits retain version history;
  renaming changes the Collection filename and title without losing the missing
  original's reference. Opening an older version alone never makes it latest.
- Collection copies open in their original groups, replacing the special
  Collection Backups routing. Legacy Backups tabs migrate to a matching source
  group, or General when no source tab is available.
- Internally, editable files are independent of the deduplicated history objects.
  Existing snapshots remain intact, saved edits join the same history, and
  unchanged bytes do not add a revision. Managed editable documents survive
  Collection relocation and are protected from automatic storage-cap cleanup.
