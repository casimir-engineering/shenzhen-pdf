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
