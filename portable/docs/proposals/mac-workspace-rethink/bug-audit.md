# Sidebar mode availability regression

In commit `6b005c8bc`, the Chapters and Comments rows could remain disabled
after switching documents while Groups or Collection History was selected.
`rebuildSidebar` returned early through `showSidebarWorkspacePanel` or
`collectionShowSelectedHistoryPanel` before it refreshed the per-document
enabled states. A later rebuild on a document with an outline or comments did
not necessarily occur until the user left the workspace panel, leaving the
rows gray even though the selected document supported them.

The fix moves segment and content-availability synchronization ahead of those
early returns. The helper reads the active content model (PDF outline/comments
or Markdown chapters/search), updates modes by their stable semantic tags, and
keeps Markdown's Comments mode absent. Ordinary list rebuilds retain their
existing fallback selection rules.

Headless regression coverage exercises disabled-to-enabled transitions while
Groups remains selected, then checks Markdown's chapter availability and the
production call order before the early-return route. `make -C portable
mac-sidebar-outline-tests` and `make -C portable mac-sidebar-workspace-tests`
pass. `ShenzhenPDFMac.mm` also passes a headless `clang++ -fsyntax-only`
compile. No app was launched.
