# Reader refinements — 5 October 2026

## Requested behavior

1. Rotate images and save their orientation.
2. Display a complete, selectable, multiline path in Properties.
3. Drag the window from empty areas at the top of both side panels.
4. Remove the bottom bar; show a source-status pill only for non-original documents, at the bottom of the left panel.
5. Make the first Fit Page after Fit Width settle image geometry correctly.

## Implementation and reasons

Image rotation is an explicit background edit, using the existing ⌘R / ⇧⌘R commands. JPEG changes orientation metadata without reencoding its compressed pixels. Other ImageIO-writable formats permute decoded samples without resampling or converting the color space. Existing EXIF orientation is applied before the new turn. Temporary-file encoding, an unchanged-source check, and atomic replacement keep a failed edit from damaging the source. Collection protects the previous version before writing; completed edits refresh the reader and Collection. Read-only copies require saving a copy. Formats without a writable encoder require a PNG copy. Rapid rotation commands queue in order; the queue is created only on the first image edit.

Properties keeps the complete path rather than a truncated presentation. Character wrapping handles long filename components; the noneditable field retains native partial/full selection and copy.

Dedicated header drag surfaces route empty space through the existing macOS window-drag/double-click policy. Sidebar buttons keep their full native hit targets. The old bottom footer is removed. Collection copies, read-only working copies and unsaved images get a compact source pill in the sidebar. History and Groups reserve the same bottom space, so their content does not sit behind the pill. Original files have no source pill. Existing OCR/translation progress panels remain available.

Fit Page establishes its required scrollers before calculating zoom. A scroller left over from another fit mode must not consume space used in the calculation. The pane-divider targets end above macOS's bottom-edge window resize zone, preventing the footer removal from creating competing resize targets.

## Native layout evidence

These are synthetic document fixtures rendered through the production reader into offscreen PNGs. The user's running app was not launched, quit or captured.

Original document: full-height reader, no footer or redundant source label.

![Original document reader](reader-refinements-2026-10-05/reader.png)

Collection copy: source identity appears at the bottom of the left panel.

![Collection copy source pill](reader-refinements-2026-10-05/collection-copy.png)

## Verification

- Image file tests: PNG, JPEG and TIFF reopen in MuPDF with the saved dimensions after clockwise/anticlockwise turns. Four turns preserve decoded pixels, including JPEG without reencoding. Invalid angles leave the file unchanged.
- Pixel tests: packed monochrome, 16-bit grayscale, wide-gamut RGB/alpha and mirrored EXIF orientation retain their samples and color space. Unequal X/Y resolution metadata turns with the pixels.
- Integration test: no encoding or Collection protection at reader setup; read-only and cancelled protection never write; rapid repeated commands run serially and each completed edit updates history and the reader.
- Properties model/panel tests pass. Compiling the new path test against the previous Properties panel fails its full-path selection/wrapping assertion.
- Production workspace probe passes at 1280, 880, 640 and 560 points, in light/dark themes, including PDF, Markdown, Find, History, hidden panels and presentation. It checks empty header hit routing, stationary repeated map clicks, the full History target, divider hit/cursor/drag coverage, footer removal and the source pill.
- Fit tests exercise the real Fit Width → Fit Page action sequence on a single image and compare the first/second results. With the old fit calculation, the stale-scroller regression fails as expected.
- Window chrome, sidebar navigation, tab state, Properties, launch-work policy, page wheel and updater tests pass. The updater suite covers 32 cases; the workspace probe also checks the native Check for Updates menu route without accessing the network.
- macOS app build, source size limits and whitespace checks pass. The coordinator shrank by extracting existing rotation routing; no source cap was raised.

A separate pre-existing renderer issue surfaced while constructing the unequal-DPI fixture: `mupdf/source/fitz/load-png.c` assigns the PNG X resolution to both axes in its image-info reader. This batch verifies preservation/swapping of the file metadata itself and does not modify the vendored renderer.

No release was published for this batch.

## Follow-up: continuous panel separator

The six-point exclusion added above also shortened the divider drawing, leaving a visible discontinuity at the bottom of the left panel. The divider now paints to the bottom edge. Only hit testing and resize-cursor coverage exclude the native six-point window-resize zone. The same correction applies to the map divider.

The production workspace probe now checks that the painted divider reaches the bottom and that the native bottom-edge zone remains passive, alongside its repeated click and divider-drag checks. The app is rebuilt in `dist`; the user's running instance is unchanged.

Magnified offscreen-render detail, before and after:

![Bottom separator before](reader-refinements-2026-10-05/divider-before.png)
![Bottom separator after](reader-refinements-2026-10-05/divider-after.png)

Pixel inspection confirms that all ten bottom separator pixels now have the same color; the prior render had six black pixels at its end.

The continuity assertion fails against the prior coordinator (38 failures across the probe layouts) and passes with the fix. Build, signature verification and source-size checks pass.


## Follow-up: fit-mode transitions and standalone-image colors

The Cmd+3 report exposed another viewport-measurement issue: Fit Height on a wide image needs a horizontal scrollbar. With legacy scrollbars, adding that scrollbar reduces the available height after the fit was calculated. Fit Width has the corresponding vertical-scrollbar problem on tall images. The extracted fit preparation now establishes scrollbar ownership before measuring either axis. Near an aspect-ratio boundary, where adding a scrollbar makes itself unnecessary, a single-page fit settles within both axes instead of oscillating between presses.

Native offscreen evidence uses blue and red image-edge bands to make clipping visible. Fit Page shows the complete image; Fit Height keeps both bands visible while allowing horizontal scrolling. Both panel separator lines reach the bottom in each mode.

![Landscape image, Cmd+1](reader-refinements-2026-10-05/image-fit-cmd1.png)
![Landscape image, Cmd+3](reader-refinements-2026-10-05/image-fit-cmd3.png)

The user clarified that color inversion affects standalone image tabs. These now honor **Keep Image Colors in Dark Theme**: enabled preserves the original pixels, disabled applies the dark reading theme. Byte-identical copies with generic suffixes are classified by MuPDF's actual format only on the first dark render that needs preservation. Opening and light rendering perform no new metadata lookup; the tests assert this deferred classification. The existing scanned-PDF exception remains unchanged.

Validation:

- Real Fit Page/Width/Height actions, transitions and repeated commands, with tall, wide and boundary-aspect images under legacy and overlay scrollbars. First-fit bounds, repeated zoom/frame equality and full-height panel separators pass. The previous reader fails eleven repeated-fit assertions across the same cases.
- Full production reader probe passes across four widths, both themes, PDF/Markdown/text, Find/History, hidden panels, presentation, click/drag routing and native updater-menu routing. The edge-band evidence comes from a separate offscreen fixture, never the user's app.
- Core theme and recolor tests pass, including enabled/disabled preservation, cropped renders, generic-suffix copies, lazy classification, unchanged scanned PDFs and unchanged print output. The previous core fails five new color/classification assertions.
- Reading-theme chrome, window chrome, page wheel, launch-work policy and all 32 updater tests pass. Source-size and whitespace checks pass. Existing oversized files shrank through extraction; no cap was raised.
- Rebuilt and signature-verified `dist/ShenzhenPDF.app` with its Collection helper. No running user app was restarted and no release was published.


## Follow-up: history deletion and deduplication

Collection already stores document/asset bytes by SHA-256: identical content shares one object, including across separate document histories. Consecutive identical captures are suppressed. A → B → A can retain three chronological events while storing only two content objects; Markdown asset changes can also require a new event despite an unchanged source hash. This behavior is retained.

Older History rows now offer **Delete version…** on right-click. The latest row linked to an available original offers **Delete all previous backups…** instead. The latter preserves the latest saved snapshot, document/source identity and original file; it removes older snapshots, including manually kept versions, after an explicit confirmation. A missing original's latest backup remains individually deletable. The Collection bulk action uses the same previous-backups wording and scope.

Deletion snapshots the chosen version/document before confirmation, so changing selection cannot change the target. Previous-backup cleanup chooses the latest version atomically under the manifest lock, protecting a new capture made while the confirmation is open. Existing garbage collection removes only unreferenced objects, indexes and preview files. No work is added to construction or launch.

The headless UI suite verifies native menu labels and targets, cancel behavior, deferred mutation, and selection changes during confirmation. Compiling the current tests against the prior History controller fails the new context-action assertions. An isolated store fixture verifies A → B → A deduplication, kept-history pruning, latest/source preservation, persistence after reopening, individual deletion, missing originals and shared-object survival/reclamation. Its initial rewrite fixture was corrected to pass the same explicit document-continuity identity used by real edit/external-change captures; a replacement file intentionally starts a separate history.

Collection store, integrity and cleanup tests and the full Markdown/UI integration suite pass. The app and Collection helper are rebuilt in `dist`; the user's running app is untouched. No release is published by this change.


## Follow-up: comparison belongs to history

Collection displays the latest saved copy, so its **Compare with Latest** command compared that copy with itself. The command and its unused routing were removed from Collection. **Compare with Previous** remains useful there. Older History rows now offer **Compare with Latest** on right-click; the latest History row omits it. Context comparison snapshots the clicked version rather than reading whatever row is selected afterward.

The complete headless Markdown/UI integration suite passes. Native Collection and History menu tests fail against the prior layout/controller, proving the removed command and new context action are covered. The active document and updater flow are unchanged.


## Follow-up: scrolling crowded tabs without losing groups

The old admission algorithm gave the active group's documents first claim on width, then omitted other group headers. A crowded group consequently showed a large `+59` count while hiding the rest of the workspace. With the tab-navigation agent, this was replaced by continuous document geometry and a clipped, scrollable lane. Compact collapsed headers remain pinned in actual group order around the expanded group's lane whenever they fit. If there are too many headers to fit, the full strip becomes scrollable rather than dropping groups.

Mouse-wheel and two-finger horizontal/vertical trackpad input scroll the lane without selecting a document. Left/right `+` counts appear for offscreen entries and can be clicked to move through the list. New selections reveal their tab; manual scrolling, hover and ordinary refreshes do not snap back. Add Document and All Groups remain separate controls. Renaming/hiding is explicit: hover a group name for stable rename/hide targets, use the group's context menu, or toggle an eye in All Groups. Hiding does not close documents or change the reader. Scroll buttons and group actions expose VoiceOver actions/labels.

Native offscreen production-strip evidence with 60 documents and adjacent collapsed groups:

![Collapsed groups beside scrollable documents](reader-refinements-2026-10-05/scrollable-groups.png)
![Group hover actions](reader-refinements-2026-10-05/group-hover-actions.png)

Root integration persists manual scroll per window in `session.yaml` under `windows[].sidebar.tabStripScroll`. Restoration uses existing in-memory window state, and wheel bursts coalesce into one save after 200 ms. No store access or saves happen during initial wiring; repeated workspace application cannot reset a manual scroll.

Validation covers pinned headers before/after a 60-document group; bilateral indicators and edge clamping; real NSEvent trackpad deltas; explicit selected-tab reveal; restored/manual scroll retention; 20 collapsed groups forcing the continuous-strip fallback; stable hover targets, rename/hide routing and All Groups eye controls; accessibility; and existing drag/drop, title, geometry and style behavior. The old GroupLayout compiles with the final harness and fails the pinned-header regression. Previous workspace code fails the new scroll restoration/callback checks. YAML roundtrip and coalesced-save tests pass.

Repeated scroll plus layout work measured 0.049 ms/input at 60 tabs, 0.127 ms at 200 and 0.522 ms at 1,000, so no additional geometry-cache architecture was needed. Full reader probes pass at four widths in both themes with PDF/Markdown/text, Find/History, panel click/drag, hidden/presentation layouts and updater-menu routing. Tab group integration, lifecycle/state, window chrome, launch-work policy and all 32 updater tests pass. Source-size and whitespace checks pass. The rebuilt `dist` app is signature-verified; the running user app is untouched. No release is published here.


## Correction: compact pills, overlay hover controls

The first hover implementation reserved blank width for rename/hide icons even when they were absent. This contradicted the compact-tab design. Group width now follows the name with 14 points of total inset and a 48-point minimum; Collection Backups adds only its existing identifying icon width. Hover controls overlay the trailing title, fading that text inside a transparency layer just like document-tab close buttons. Neither title geometry nor pill width changes on hover, and the action overlay stays clipped to the rounded pill.

![Compact group names](reader-refinements-2026-10-05/compact-group-pills.png)
![Overlay actions without reserved padding](reader-refinements-2026-10-05/compact-group-hover.png)

The compact-width assertion fails against the previous layout and passes with this correction. Group click/drag/scroll/hover, tab geometry/style and the full production reader probe pass. The app is rebuilt and signature-verified in `dist`; no user window was launched or interrupted.

## Correction: group visibility through the eye

All Groups now shows only the group name and document count. The eye is the same symbol in both states: normal label color for visible groups and gray for hidden groups. Clicking it updates the tint immediately; tooltips and accessible labels still explain Show/Hide without adding visible status text.

![Group picker with gray eye for a hidden group](reader-refinements-2026-10-05/group-picker-eyes.png)

Headless group interaction tests and source-size checks pass. The image above comes from the native offscreen fixture, without opening or capturing the user's app.

## Correction: keep only the hover eye

Removed the rename icon and its hover hit target. Only the hide eye now overlays the trailing 20 points, so more of the group name remains visible. Right-click **Rename Group…** still opens the existing name popup anchored to that group. Group-name clicks keep their collapse/expand behavior, including the area formerly occupied by the pencil.

![Single hover eye on a compact group pill](reader-refinements-2026-10-05/group-hide-only.png)

Headless interaction checks cover the recovered name-click area, retained context rename, stable pill geometry and hide action. Source-size checks pass.
