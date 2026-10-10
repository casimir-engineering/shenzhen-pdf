# Release notes

User-facing notes for changes merged since the last release (26.10.7 build 2).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Chat history now has folders, timestamps and short generated titles. Right-click
  to rename a chat or move it; removing a folder keeps its conversations.
- History search shows highlighted message excerpts. Search inside a chat is
  separate. Chat actions align with the reader toolbar, Hide comes first, and
  Chats shows its selected state. Empty chats no longer show a blank dark block.
- Generated chapters use plain, more descriptive titles. A successful final
  tool action no longer becomes an Error solely because the step limit was reached.

- AI chats now use a searchable history sidebar and a separate resizable chat
  panel next to the document. The Chats icon opens history; hide/reopen preserves
  the current conversation and draft. Saved conversations can be continued later.
- Undo and Redo cover supported assistant changes. The assistant can update saved
  generated chapters, summaries, tags and language, and discover native app menus
  and visible controls. Native commands report queued dispatch separately from
  successful completion and do not claim generic Undo support.
- Chat keyboard behavior handles IME composition, Return/Shift-Return, Escape,
  and Cmd-Z/Cmd-Shift-Z from an empty composer. Light/dark native layouts and full
  button hit areas have headless regression coverage.

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
- Recovery also handles originals whose metadata is visible but whose contents
  cannot be read (including restricted Safari temporary PDFs), and damaged sources.
  The red status and a rounded Locate button sit centered in the existing toolbar,
  with a compact layout for narrow windows. Recovery
  reuses the original tab when its Collection copy is already open and supports
  repeated loss of access after a source is restored.
