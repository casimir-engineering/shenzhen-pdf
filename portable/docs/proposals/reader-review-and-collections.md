---
paper-size: A4
paper-margin: 30
---
# Reader review and Collection

Independent critic · 22 September 2026 · Proposal, not implemented

## Improve the existing reader

**Save reading positions during use.** After jumping to Markdown page 3, waiting over 12 seconds and abruptly restarting, the app returned to page 1. The saved session still held the old position. Checkpoint navigation and debounce scroll saves. Verified crash-recovery gap; graceful quit was not tested.

**Make tabs accessible.** The actual accessibility tree exposes the toolbar and document but no tabs. Add names, selection, group state, keyboard actions and shortcut help, keeping the approved compact appearance.

**Add Move to Group and grouped overflow.** Source inspection shows New Group without an existing-group destination, and overflow lists filenames without group identity. Add destinations with colors and membership checkmarks; organize overflow by group. These group interactions remain unverified live because computer-use coordinate clicks failed.

**Improve editor selection and copy labels.** The first editor picker visibly starts in the document folder with all files disabled: start in Applications. Context menus should say “Copy Page 3 as PDF/Image” so the target is clear. Copy output itself was not tested.

The table fix, A5 layout and explicit page breaks looked good. Tabs, selected document and window geometry survived abrupt restarts. Group creation, colors, dragging and group persistence still need hands-on verification.

## Collection: the everyday experience

“I opened a supplier drawing last month, then moved the original. I want to find my saved copy and compare it with today's revision.”

Collection remembers documents after their tabs close. One Collection has **Documents**, containing each first-seen original, and **Versions**, containing its history. Tab groups organize the current workspace. Collection is local recovery history, not a backup on a separate device.

**First use:** propose Collection enabled, but ask once before retaining contents: “Keep a local copy of documents you open? You will continue using the originals. Copies stay on this Mac; change this in Settings.” Offer **Keep Enabled** and **Turn Off**. Reading starts immediately; capture waits for the answer. Remember the choice. Do not silently import existing recent-document history.

**Opening:** always display the live source at its original path. Capture a complete copy in the background. History shows capture progress or failure; failed capture must never imply protection.

**Search:** add Collection to **Ctrl+K**, retaining macOS **Cmd+K** as well. Search names, titles and paths immediately; index contents lazily. Show live sources before unavailable collected documents, one result per document with versions collapsed beneath it. A normal result opens the original whenever available.

**History:** add **Previous Version** and **Version History…** to the tab menu. History opens in the existing left sidebar. An archived preview has a persistent **Archived copy · read-only · date** badge and never replaces the live source silently.

## Preserve, inspect and compare versions

Before ShenzhenPDF modifies a file, preserve its current bytes durably. Only then overwrite the source and capture the completed revision. If protection fails, offer **Retry**, **Cancel edit**, or explicit **Continue without history**. Reading remains available.

External edits have a narrower guarantee: retain the last observed version and capture the next stable saved version. Do not promise every intermediate revision or changes made while the app was closed. Keep capture times honest.

History shows date, size and reason: First opened, Before annotation, External change detected. Identical contents create no extra revision. Coalesce repeated autosaves into edit sessions while preserving the pre-edit and latest versions. Let users mark useful versions **Keep**.

Selecting a version opens a read-only preview. Offer **Compare with Current**, **Compare with Previous**, and **Save a Copy…**. Comparison uses a split viewer with dates, synchronized scrolling and next/previous change controls. Identify inserted or removed pages so later pages are not falsely reported as changed.

Use text differences for Markdown. Start PDF comparison with changed-page thumbnails and visual overlays or side-by-side pages; do not promise semantic PDF or scan differences. Rendered Markdown comparison can follow for tables and layout.

**Save a Copy…** creates an independent ordinary file. A later **Restore over Original…** action would require an explicit destination and a protected copy of the current original. Stored archive versions remain immutable.

## Recovery and user control

If the original disappears, keep its tab with a red warning outline and unavailable-source symbol. Preserve the group color on the group boundary. Say **Original unavailable**, offering **Open Archived Copy**, **Locate Original…**, **Save a Copy…**, and **Retry**. Show the archive date. Open it in a distinct read-only tab; keep the original marked unavailable. A disconnected drive is not a deletion.

Verified renames and moves retain history. A normal atomic save of the watched source is a version even if its file identifier changes. An ambiguous unrelated replacement at the same path starts a separate entry unless the user links it. Identical files at different paths remain separate documents; deduplicate their stored bytes only. Validate Locate Original candidates and expose uncertainty. Old locations remain searchable; closing a tab never removes history.

Settings offers **Collection On/Off**, location, storage used and **Manage Collection…**. Turning off stops new capture and indexing while preserving existing search, export and deletion. Say this beside the switch.

Manage Collection removes a version, document history or all archived data with explicit scope. It never deletes source files. **Exclude this document** prevents future collection; one-time archive deletion is a separate choice.

Default to **Keep all**. Offer an optional user-set limit, but pause capture when full instead of silently deleting the first copy or kept milestones. Protected, oversized or unavailable documents need clear capture status. The reader stays usable.

Markdown archives include bounded local linked assets, relative paths and a manifest. Flag missing or excluded dependencies. Never fetch network resources to archive them; remote content is not guaranteed offline.

## Delivery and implementation

**First:** consent, full-copy archive, searchable index, correct original/archive routing, read-only previews, missing-source recovery, app-owned pre-edit checkpoints, sidebar history, storage and deletion controls.

**Next:** stable external-change capture, dependency-aware Markdown archives and comparison. Flag incomplete asset capture from the first delivery; do not imply offline fidelity until supported.

**Later:** compression or block deltas only if measurements justify them. Every revision must remain reconstructable, verifiable and exportable. Full copies with hash deduplication come first; optional APFS clones can accelerate copying.

Keep source identity, immutable archives and session state separate. Use stable document IDs, file bookmarks/path aliases and an indexed manifest. Existing mutable read-only working copies are not version history. Read-only archive views never change source permissions.

No startup scan, hashing or copying. Bound background work after open, snapshot consistently, and retry if the source changes during capture. Gate app-owned writes on the durable snapshot. Debounce relevant file watchers; unchanged files need cheap metadata checks. Coordinate windows to avoid duplicate capture. Keep storage private; preserve source encryption and avoid indexing decrypted text by default. Do not automatically OCR scans.

Acceptance checks must cover rename, same-path replacement, offline recovery, failed snapshots, multiple windows, disable/exclusion/deletion across relaunches, immutable previews and independent exports. Prove Collection-off and ordinary launch add no archive work.

The user should always know whether they are reading the original, a saved version or a comparison—and whether the latest revision has actually been protected.
