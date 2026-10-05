# Release notes

User-facing notes for changes merged since the last release (26.10.2 build 4).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Rotate writable images with **⌘R / ⇧⌘R**; the saved orientation survives reopening. JPEG rotation preserves its compressed pixels.
- **Properties** shows the full file path, wrapping onto multiple lines and allowing partial or complete copying.
- Drag the window from empty space in the Chapters/tools header or the map header.
- Removed the bottom status bar. Collection/working-copy status appears only when relevant, as a pill at the bottom of the left panel.
- Fixed the extra space after **Fit Width → Fit Page** on images; the first Fit Page now settles the scrollers before measuring.

- Fixed the broken separator line at the bottom of the left panel; its drawing now reaches the edge while mouse handling preserves the native window-resize zone.

- Fixed first-press fitting in **Fit Height** and **Fit Width** too: scrollbar changes no longer clip the image bottom or change the fit on the next press.
- Standalone images retain their colors in dark mode while **Keep Image Colors in Dark Theme** is enabled; turning it off applies the dark theme. This also works for image copies with a generic filename extension.

- Right-click a saved History version to **Delete version…**. On the linked original, **Delete all previous backups…** removes older snapshots while retaining the original and latest saved copy. Collection’s former “Delete Selected Copies” action now uses that name and scope.

- Removed self-comparison from Collection. **Compare with Latest** is available on older History versions’ context menus and uses the clicked snapshot.

- Scroll crowded tab groups with the mouse wheel or a two-finger trackpad gesture. Other collapsed group names remain visible when they fit; left/right `+N` tabs overlay the lane with a fade and open lists of offscreen documents without moving the strip. Scroll position persists per window.
- Hover a compact group name for a **Hide** eye overlaid on fading text, without reserving empty pill space. Right-click **Rename Group…** keeps the name editor anchored to the group. The All Groups picker includes eye toggles to show or hide groups without closing documents; hidden groups have a gray eye, without extra status text.
