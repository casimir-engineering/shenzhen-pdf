# Release notes

User-facing notes for changes merged since the last release (26.10.5 build 1).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Drag a tab onto another tab in the same group and pause briefly to create a new group, with its name ready to edit. Quick drags and edge drops still reorder tabs.
- **Rename Document…** is now available in the tab context menu. It renames the file in its existing folder, preserves its extension and open reading state, and updates the Collection source link.

- Brighter tab-group colors replace the muted palette. Inactive tabs show their group tint more clearly; selected tabs use richer shades, with readable titles in light and dark mode.

- Icons retain their natural proportions throughout reader toolbars, sidebar navigation, group controls and Collection buttons, without changing click targets.

- ⌘K matches multiple words across open-document names and paths in any order. Exact document names rank first, followed by filename matches and then folder context—for example, “assembly R2” finds “Assembly guide” inside “Original R2”.

- Reader buttons respond reliably to the first click after moving the window or clicking another control quickly. The titlebar search icon uses explicit press/release tracking.
- Standalone toolbar icons retain their size but use compact 24-point click targets, leaving more room around them to drag the window. The zoom menu no longer overlaps the next-page button’s edge.

- The left panel toggle stays at the left edge on the reader toolbar’s baseline. Chapters, Search, Comments and History are centered between separators; Groups stays at the right.
- Escape dismisses the top-right Groups menu before clearing an active document search. A second Escape returns to the previous panel.
- Missing documents show a centered **Locate document** action. It and the tab’s recovery command open automatic search/manual selection directly, rather than only opening History. Recovery is omitted for available originals. Uncollected files can be searched by filename, with candidates clearly distinguished from verified hash matches.
- History keeps a **Missing document** entry when the original is lost, and labels the newest saved version **Latest copy**. Reconnecting the original removes the missing entry and restores **Latest**.

### Continuous group underlines

Group underlines remain continuous beneath the left and right +N overflow badges. The tab-content fade excludes the underline instead of erasing the entire strip height. Offscreen pixel checks cover both badges in light and dark appearances; tab scrolling and overflow-menu interaction tests pass. Sidebar layout checks verify centered document tools, usable narrow-panel targets and unchanged toggle coordinates.

### Multiword document lookup

Open-document palette matching requires every whitespace-separated query term, without requiring their order or adjacency. Case and diacritics remain ignored. Exact title/filename matches (including extensionless names) outrank phrase prefixes, contained phrases, unordered filename words and finally full-path context. Existing recency/order tie-breaking remains intact. Matching uses in-memory candidate strings only; it does not read files or add launch work. Regression coverage includes the Assembly guide/R2 folder example, exact-name priority over more recently focused path matches, reversed words, whitespace and exclusion of unmatched revisions.

### Proportional icon drawing

Custom chrome drawing now shares a centered aspect-fit geometry helper. Previously several SF Symbols were stretched into square destinations, including the sidebar, toolbar, group picker, group visibility action and Collection controls; segmented toolbar drawing only preserved proportions for two-segment controls. All these paths now fit the natural image size inside the existing slot. Native image views already use proportional scaling. No document-rendering path or launch work changed. Tests cover actual wide/tall symbols across 10–24-point slots, centering, containment and unchanged interaction behavior.

### Brighter tab-group palette

Refreshed the existing named palette with lilac, mint, sky blue, turquoise, rose, peach and golden accents. Increased inactive-tab tint from 6% to 16%, hover tint from 16% to 27%, and group-pill tint from 16% to 24%. Selected fills retain at least 4.5:1 black/white title contrast in the existing tests. Green and Teal now have distinct selected fills. Orange was tuned to preserve the separate pale Collection-copy outline. Names, persisted group color choices, dimensions and interactions are unchanged. Native light/dark fixture renders and group model/integration/interaction tests pass.

### Same-group drag grouping and document rename

Removed the blanket same-group exclusion in center-hover group detection. The source group handle remains a reorder target; a brief center dwell splits sibling tabs into a new pair using the existing naming prompt. Joining another custom group remains available. Regression coverage exercises General and custom groups, quick reordering, center grouping, overflow placement and document-specific context-menu routing.

Document rename uses a native sheet prefilled with the filename stem. Invalid names are rejected and existing files are never overwritten. The open tab, active path, Markdown session URL, group last-used path, recent list and persistent workspace are updated. Collection copies, unsaved captures and missing files do not expose an actionable rename. Collection relinking is serialized in the background to keep file hashing off the UI thread; a failure is reported without pretending the history link succeeded. Filesystem tests cover extension retention, unsafe names, unchanged names, byte preservation and collision safety.
