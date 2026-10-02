# Release notes

User-facing notes for changes merged since the last release (26.10.2 build 4).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Sidebar icons, including History, use the full visible button area for native click tracking.
- Crowded tab groups now use the available strip width, keeping Add Tab beside Group Management without widening sparse groups.
- New groups have a simpler naming dialog: edit the selected default or press Enter to accept it.
- Drag documents between groups in the Groups panel. All groups temporarily collapse during the drag, including while filtering, to expose destinations; cancelling restores the previous view.
- Group headers in the Groups panel use the same pastel backgrounds as the tab bar.
- Collection Backups always uses pastel Orange. Saved copies may move to other groups and retain a distinct pale-orange outline and their saved membership across relaunches.
- Fixed unreliable sidebar navigation clicks across Groups, Chapters, Search, Comments and History by removing the legacy segmented-control parent behind the custom icon buttons.
- The top-bar Groups button reliably opens and closes its popover on consecutive clicks, without waiting or moving the pointer.
- Collection entries without a saved copy now load a preview lazily from the original when their row is viewed. Refreshing rechecks the original; historical previews never substitute a different version.
- Fixed intermittent resize drags after tab-bar interactions and competing document cursors over pane dividers. Map and left-panel handles have consistent hover/drag targets on both sides, with unchanged visible gutters and document spacing.
- Collection reuses the verified working copy after a protected document is successfully read, avoiding a second permission-dependent read of the original. Successfully loaded background tabs are captured too.
