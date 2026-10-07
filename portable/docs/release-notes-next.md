# Release notes

User-facing notes for changes merged since the last release (26.10.7 build 1).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Document-search failures are displayed in the Search panel instead of appearing as zero matches. If a background document read fails, press Enter to retry; invalid regex errors are also visible.

- The tab-strip **+** now offers **New Tab** and **New Group…**. Create an empty group while continuing to read the current document, then open files into it. Empty groups and their next-open destination persist across launches; they support naming, colors, visibility, closing, and drag-in documents.
