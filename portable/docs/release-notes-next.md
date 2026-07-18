# Release notes

User-facing notes for changes merged since the last release (26.7.17 build 1).
When cutting the next release, run ./portable/cut-release.sh — see "Cutting a
release" below. The in-app updater shows the section above the first ---
of the release body as plain text (500-char cap).

## Cutting a release

Run `./portable/cut-release.sh [--dry-run] ["commit summary"]`. It derives the
date-based version, bumps it everywhere, runs all tests, builds + notarizes the
DMG, tags, pushes, and publishes the GitHub release. Notes are read from
`dist/release-notes-<ver>-<build>.md` (highlights above a --- divider, details
below); if that file is missing the script seeds it from the section below and
stops so you can edit it.

## Next release

- Settings, session, documents, favorites, and bookmarks state files are now
  human-readable YAML (`settings.yaml`, `session.yaml`, ...) instead of JSON.
  Existing files are migrated automatically on first launch; the old `.json`
  files are kept next to them as `<name>.json.migrated-backup`. The Settings
  menu entries now open the YAML files.
