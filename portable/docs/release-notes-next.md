# Release notes

User-facing notes for changes merged since the last release (26.8.28 build 2).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Settings, session, documents, favorites, and bookmarks state files are now
  human-readable YAML (`settings.yaml`, `session.yaml`, ...) instead of JSON.
  Existing files are migrated automatically on first launch; the old `.json`
  files are kept next to them as `<name>.json.migrated-backup`. The Settings
  menu entries now open the YAML files.
