# Native workspace verification

The implementation is checked against `reader-workspace.fragment.html`. The browser proposal is a visual contract for chrome and information hierarchy; document rendering, the working map, search, updater, Collection storage and YAML state keep their native behavior.

## Headless reader evidence

Run from the repository root:

```sh
make -C portable -f Makefile -f mac/tests/workspace-probe.mk -j4 \
  mac-workspace-probe WORKSPACE_EVIDENCE_DIR=/tmp/sz-workspace-native
```

`SPDFMacWorkspaceProbe.mm` links the production reader and calls its actual window builder. It does not call the application entry point or launch delegate. It creates a private temporary state directory and a three-page PDF with outlines, supplies those pages to the real document canvas and map, and loads a Markdown document through the real session renderer. The fixture captures the view hierarchy with AppKit bitmap caching, never with a screenshot of the user's app. A fail-fast override rejects any attempt to order a window on screen. Disk persistence is stubbed at the delegate boundary.

The evidence matrix covers light and dark appearances; 1280, 880 and 640-point windows; both side panels; hidden panels; presentation chrome; the real Find query/results panel; and the Markdown host. The native menu's Check for Updates item is located and validated. Its action must reach the updater as an explicit user request; the network entry point is replaced only during this assertion.

The probe uses incremental objects under `portable/build/workspace-probe/`, allowing repeated visual checks without relinking the app bundle or disturbing `dist`. PNGs and geometry output are evidence, not a pixel-perfect baseline: platform font rendering can vary. Review alignment, title clipping, selected tabs, tool discoverability and header boundaries directly.

## Regression gates

| Area | Commands | Required outcome |
|---|---|---|
| Update and release | `make -C portable mac-updater-tests release-pipeline-tests` | Version comparisons, exact-tag health checks, download limits, signing gates, safe publication and rollback contracts pass. No live update is installed. |
| Tabs and groups | `make -C portable mac-tab-strip-geometry-tests mac-tab-strip-interaction-tests mac-tab-strip-style-tests mac-tab-group-tests mac-tab-group-interaction-tests mac-tab-state-tests` | Correct hit targets and overflow; complete title metadata; collapse keeps the active document; drag ordering and persistent groups remain intact. |
| Sidebar and state | `make -C portable mac-sidebar-navigation-tests mac-sidebar-workspace-tests mac-group-management-tests mac-state-yaml-tests` | PDF/Markdown capabilities update with document switches; direct buttons and keyboard modes work; group/query/visibility state round-trips; hidden panels stay lazy. |
| Reader/map/window | `make -C portable mac-window-chrome-tests mac-window-shortcut-tests mac-minimap-window-tests mac-reading-theme-chrome-tests mac-launch-work-policy-tests` | Header controls retain hit ownership; map geometry and theming remain functional; restored frames and launch deferral remain intact. |
| Collection and command search | `make -C portable mac-collection-store-tests mac-collection-search-tests mac-collection-palette-tests mac-palette-results-tests mac-collection-reader-navigation-tests mac-collection-companion-link-tests` | Ranked results and navigation stay correct; collection storage is unchanged; helper links its exact source set without the reader or updater. |
| Markdown/native integration | `make -C portable mac-markdown-tests` | Rendering, host integration, comments availability, Collection previews and history continue to work at production optimization. |
| Packaging | `make -C portable mac-app`; `tools/check-file-sizes.sh` | Fresh reader and helper bundle build successfully, matching source artifacts; size limits hold. |

Check test exit codes. A printed success substring cannot substitute for the runner's result. Rebuild a target after relevant source changes before trusting an earlier pass.

## Integration risks to review

- The app globs `mac/*.mm`; Collection deliberately uses `mac/companion/sources.mk`. Shared chrome dependencies must be available in both without dragging the reader, MuPDF or updater into the helper.
- The Markdown integration runner has its own explicit source list. A production build alone does not prove the headless suites link.
- Sidebar modes are persisted identifiers. Their visual order can change without changing the identifiers stored in YAML.
- Extending panel headers into the toolbar row changes coordinate relationships. Check PDF and Markdown hosts, sidebar resizing, map hiding, short windows and presentation independently.
- Collapsing a group must change layout only. It must not change the active document or overwrite that document's position.
- Tab-only extension removal must not alter path identity, filenames in the sidebar, accessibility help, duplicate resolution, menus or updater assets.
- The updater launch hook remains deferred until first paint, its health handshake precedes scheduled checks, and every supported window process retains recurring checks. Chrome construction must not invoke these services.

## Baseline, 1 October 2026

Before completing the overhaul, `mac-updater-tests` and `release-pipeline-tests` exited 0. The updater reported 32 cases and release workflow reported 56 passed, 0 failed. The native workspace probe also exited 0 after integration: 14 light/dark PNGs, real PDF and Markdown hosts, real Find search results, presentation restore, updater menu routing, retained filename extensions, untruncated zoom labels and non-overlapping visible toolbar controls. Markdown capture waits for `navigationReady`, since Ready precedes the deferred viewport reveal. Repeat the remaining gates after the final production edits. No release was published and no running application was replaced by these checks.
