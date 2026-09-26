# Whole-reader redesign: decision and validation

25 September 2026. **Interaction proposal, not a shipped interface redesign.** The separate Chapters/Comments enablement fix is built in `dist/ShenzhenPDF.app`; see [bug audit](bug-audit.md).

## Latest revision: shared alignment grid

26 September 2026, after the alignment feedback. The window now uses one grid for navigation, the task pane, document controls, canvas and footer. The pane heading sits alongside the reading toolbar, instead of starting a row below it. Workspace heading, pane heading and reading toolbar have the same 44px height and top coordinate. Tabs begin at the navigation column's right edge. Group labels, document tabs, close buttons and title-bar search share the same vertical center. Navigation uses 36px rows, 16px icons and consistent 8px gaps. The footer spans the entire window.

Browser geometry confirmed identical header tops/heights and identical tab-control centerlines; the tab start and rail edge differed by under 0.01 CSS px from rounding. The compact History drawer begins exactly below the toolbar and ends at the footer, including the older-version status row. No horizontal overflow was observed in either checked size. Closing the task pane returns its width to the canvas. No browser console errors were observed. These remain prototype checks, not native app changes.

![Aligned whole reader](evidence/aligned-reader-desktop.png)

![Compact History with aligned drawer boundaries](evidence/aligned-compact-history.png)

## Previous revision: Brave-style tabs

26 September 2026. The user requested Brave's tab system. Read-only inspection of the already-running Brave window supplied the horizontal tab shape, spacing, selected surface, close control and trailing plus/dropdown arrangement. No Brave tabs or settings were changed. Brave's [compact horizontal tabs issue](https://github.com/brave/brave-browser/issues/40044) was also consulted as a supplementary primary source.

The proposal now uses individual rounded tabs with file icons, trailing close buttons, a distinct selected surface and equal title foreground colors. Compact colored group labels and a continuous line beneath expanded members replace the enclosing capsules. Tabs remain fused with the title bar. Clicking a group label expands/collapses its members without switching the document; selecting a document collapses the other groups. The plus opens a synthetic document picker, and the trailing dropdown opens the complete group inventory. These are local prototype interactions, not native file operations. Dragging, full context menus and cross-window group transfers remain outside this visual revision.

Browser checks covered expanded groups without document changes, closing/reopening a tab, PDF/Markdown switching, dark/light appearance, and a 323px-wide header without horizontal overflow. Browser console errors: none observed. Close state and expanded groups join the prototype's existing saved state. The following images supersede the older tab styling below.

![Brave-style tabs in dark appearance](evidence/brave-tabs-desktop.png)

![Brave-style tabs in light appearance](evidence/brave-tabs-light.png)

## Previous revision: tabs share the title bar

Following user feedback, grouped document tabs now sit beside the window controls in the top bar, preserving the current app's organization. The separate application-title row and lower tab row are removed. Cmd+K remains at the right as a compact search control. This returns the previous tab row's height to the document and task pane. The header fits desktop and narrow widths without horizontal overflow; its search button still opens the command palette. Earlier captures below record the preceding review; this is the updated composition.

![Tabs fused with the top bar](evidence/fused-topbar-desktop.png)

## Why the previous pass failed

It optimized the vertical size of individual components while retaining the wrong hierarchy. Global workspace management, current-document navigation, search and saved-version management still competed in one stack. Synthetic component tests established that controls fit, not that the entire reader made sense. The previous numerical scores did not establish that outcome.

This pass began with the native reader's source and a read-only accessibility inspection of the running interface. It observed a 72-tab session with four groups and 63 documents in General, plus a toolbar mixing reading, Find, Regex, OCR, translation and Map. No app was launched, quit, navigated or screenshotted. The mockup uses synthetic filenames/content rather than the user's documents.

## Proposed organization

| Area | Responsibility | What changes |
|---|---|---|
| Unified title bar and grouped tabs | Choose the current document; find anything across the workspace | Window controls, grouped tabs, inventory overflow and compact Cmd+K share one row. Retains group identity, stronger selected-tab color and ordered document/group/text/Collection search scopes. |
| Task rail | Choose what to do | Workspace: Groups and Collection. Document: Chapters, Find, Comments where supported, History. Icons precede labels. |
| Single task pane | Show the chosen task's content | List/query begins at the top. No permanent five-row selector above it. One task owns one pane. |
| Reading toolbar | Navigate and size the document | Page controls and zoom stay together. Occasional tools live in a labeled Document Tools menu. |
| Source/version status | Explain which bytes are being read | Older date plus Return to Latest persists after History closes. Missing original remains a readable saved copy with recovery choices. |
| Collection companion | Browse saved documents and settings | Preserves its separate-window role, Documents/Settings navigation, latest-only list, thumbnail with contextual matches. |

**Final prototype dimensions and naming supersede the initial alternatives' draft numbers.** The rail is 102px at wide sizes, 92px below 780px; the task pane is 218px/208px. Its cost is roughly 80px more horizontal space than the prior 240px sidebar when open. It returns the full pane height to information. Closing the pane leaves only the rail. At 650px or narrower, or content height below 370px, a labeled vertical panel chooser replaces the persistent rail and the task pane becomes a closable drawer. It never scales down the whole interface to fit.

Groups keeps the user's **group-name-only** filter. Finding a document among 72 uses Cmd+K; no additional search scope or separate membership model was introduced. The root prototype retains the familiar Chapters/Comments names rather than renaming them Outline/Notes. Collection stays a companion, not a cramped rail pane. The comparison view is an interaction study of the paired reader task; native window ownership is an implementation decision, not changed by this file.

The design controls expose the second alternative: a compact panel chooser at every width. It saves the rail's width but costs an extra action when changing tasks. They also expose document condition and window-content height. This is a deliberate tradeoff to evaluate, not a hidden replacement for the requested vertical navigation.

## Primary-source study

Apple Preview distinguishes document sidebar views from page/zoom commands, and supports hiding the sidebar and customizing the toolbar. That supports separating navigation content from persistent reading commands; it does not prescribe ShenzhenPDF's group or Collection model. [Preview: view PDFs and images](https://support.apple.com/en-by/guide/preview/prvw11470/mac).

Pages distinguishes its navigation sidebar from contextual formatting/document controls. The useful lesson is scope separation, not blindly adding a second permanent inspector to a reader. [Pages: use sidebars](https://support.apple.com/guide/pages/use-sidebars-tan0870f78aa/mac).

The visualization skill supplied an inspectable interaction surface and alternative controls. The design method here was scope inventory, task-flow mapping, state/return contracts, responsive whole-window inspection, and independent criticism. It is not evidence from participant research.

## Review and corrections

The independent critic inspected the entire reader at 1024px and challenged workflows, not isolated sidebar images. The first prototype exposed lost document state, fabricated search hits, incorrect hidden-group display and weak modal behavior. These were corrected before presenting it:

- Document switching retains page, query/Regex, zoom, selected version and scroll position per document. Markdown has no Comments destination; returning to PDF restores supported navigation.
- The complete 72-document synthetic inventory exists; General can expand into 63 rows. Expansion does not change the document. Hiding the active group removes its strip and leaves the document readable with explicit status.
- Find, Cmd+K and Collection use finite fixture text; no-match and invalid-pattern states are explicit. Text hits carry a document/page destination. Map markers derive from actual results.
- History keeps dated read-only identity outside the pane. Latest page 7→older page 13→Return to Latest restores page 7. The selected version and original file are not conflated.
- Dialogs make the underlying interface inert, move focus inside, contain Tab traversal and restore the invoker. Collection's lower settings scroll into view at the minimum fixture.
- At 560×380, the older-version badge initially clipped. It now occupies a separate toolbar row with its complete date and an always-visible Return to Latest action.

[Independent review record](critic.md).

## Browser checks actually performed

| Check | Observed result |
|---|---|
| Whole reader 1024×720 | Task rail, full-height pane, page and Map fit; ordinary reading controls remain grouped. |
| Busy groups 800×500 | General exposes 63 rows in a bounded list; page remains readable; no horizontal window overflow. |
| Compact 560×380 | Chooser exposes workspace/document tasks; closed History retains full dated status and Return to Latest. |
| Compact Collection settings | Dialog 272px inside a 346px mock window; lower Set location/Open location controls reached and captured; no horizontal overflow. |
| PDF→Markdown→PDF | Markdown Comments absent; PDF Comments restored; original document page 7 retained. |
| Search and empty result | Power sequencing gives 3 fixture matches; nonsense gives 0; closing pane keeps 0 map markers. |
| Global text jump | Sensor selects Interface specification, page 1, with 1 real fixture match. |
| Revision return | Latest page 7→older page 13→Return to Latest returns to 7. |
| Active group hidden | Its tab strip is hidden; reader continues showing the same document; source status identifies the hidden group. |

The medium/compact HTML fixtures use the same fragment with only the configured content height changed to 418/296px. This makes 800×500 and 560×380 browser captures fit their complete mock window; they are not tall pages cropped to look compact. Icons are initialized asynchronously by the visualization runtime; evidence was captured after the placeholders became real SVG icons.

## Evidence and limits

![Whole reader](evidence/reader-1024.png)

![Find in the whole reader](evidence/find-1024.png)

![Groups at 800×500](evidence/groups-800x500.png)

![Older version at 560×380](evidence/older-560x380.png)

![Reachable compact Collection settings](evidence/collection-settings-560x380.png)

These are browser prototype captures, not the native app. Viewport dimensions include the preview wrapper’s 16px margins; the compact mock window itself is 528×346px. PDF/Markdown rendering, drag-and-drop group movement, native file dialogs, OCR/translation, actual archive writes, VoiceOver, every keyboard binding and production comparison performance are outside this prototype. Native actions show their destination without operating on files. The example document body is synthetic and repeated across fixtures; identity/selection/return behavior is the tested part. No claim is made that this browser prototype proves native YAML persistence or fixes unreported production bugs.

Before implementing the redesign, the native integration work must preserve one tab/group model, one current-document Find state, stable version identity, per-document return points, YAML geometry/state and zero additional startup work. Replace layout composition first, not those models. The visual proposal remains separate from the tested native bug fix.

Final search checks also verified that “timing” labels and opens page 4 with its literal passage, and `col:sensor` opens Bench measurements at page 1 with one highlighted match and saved-copy status. The final browser console showed no errors.
