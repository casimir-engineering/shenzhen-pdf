# Release notes

User-facing notes for changes merged since the last release (26.10.7 build 1).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Document-search failures are displayed in the Search panel instead of appearing as zero matches. If a background document read fails, press Enter to retry; invalid regex errors are also visible.

- The tab-strip **+** now offers **New Tab** and **New Group…**. Create an empty group while continuing to read the current document, then open files into it. Empty groups and their next-open destination persist across launches; they support naming, colors, visibility, closing, and drag-in documents.

- Fixed chapter expand/collapse clicks, including the all-chapters toggle and individual disclosures. Chapters now uses the same outlined expand/collapse icon as Groups.
- Chapters, Comments, Groups, and document Search now share consistent rounded search fields, font size, height, and spacing.
- Escape from a panel filter clears it and returns focus to the document, so immediately typing starts a fresh document search instead of continuing to filter the panel.
- Sharper control icons when resizing panels: icons keep their proportions and redraw without requiring hover. Sidebar buttons align to screen pixels; toolbar and panel icons use vector sources rather than resized bitmap copies.
