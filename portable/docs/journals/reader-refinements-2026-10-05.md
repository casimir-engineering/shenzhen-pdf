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
