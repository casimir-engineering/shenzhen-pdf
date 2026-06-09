# Implementation Journal

Date: 2026-06-03

Scope: prompt-linked implementation journal for the current working tree. This records what was changed, what was tested, and what is still not complete.

## Original Prompt Tracker

1. Refactor the 10k-line `.mm` file and keep an eagle view of oversized files.
   - Status: Partially complete, not done.
   - Changed: extracted Mac models, tab strip, document view, minimap, print view, and shortcut-help delegate behavior into dedicated files under `portable/mac/`.
   - Current line counts: `portable/mac/ShenzhenPDFMac.mm` is 8,502 lines; extracted Mac files are 99-749 lines except `SPDFMacMinimapView.mm` at 604 lines and `SPDFMacDocumentView.mm` at 578 lines, plus `SPDFMacDelegatePrivate.h` at 357 lines and `ShenzhenMacDelegate+ShortcutHelp.mm` at 234 lines. `portable/linux/ShenzhenPDFGtk.c` is 9,130 lines after one helper extraction.
   - Gap: the Mac and Linux monoliths are still too large. Next refactors should split session/window lifecycle, rendering/cache orchestration, palette/favorites, sidebar/comments, and Linux minimap/session code.

2. Closing the last document in a non-last window should close that window, not show “no file loaded.”
   - Status: Implemented for the current Mac multi-process window architecture; manual multi-Space QA still needed.
   - Changed: `closeTabAtIndex:` removes the current session window and terminates only this process when another Shenzhen window/process exists. The empty view remains only when no other Shenzhen window exists.
   - Gap: restored windows still use separate processes; true single-process multi-window restore remains a larger architecture task.

3. Duplicate same-name tabs should add enough path context and collapse repeated folders with `...`.
   - Status: Implemented for Mac, Linux, and Windows.
   - Changed: Mac `spdf_disambiguated_display_names_for_paths`, Linux `spdf_gtk_disambiguated_tab_title`, Windows `DisplayTabTitleTemp`.
   - Tested: Mac and Linux runtime checks for `/root/documents/folder1/folder2/test.pdf` and `/root/invoices/folder1/folder2/test.pdf` returned `documents/.../test` and `invoices/.../test`.

4. Add Shift+Cmd/Ctrl+F presentation shortcut.
   - Status: Implemented for Mac, Linux, and Windows.
   - Changed: Mac adds `Cmd+Shift+F`, Linux/Windows add `Ctrl+Shift+F`; F5 remains.
   - Tested: build/syntax coverage only. Runtime shortcut QA still needed on all platforms.

5. Presentation mode should launch when already fullscreen on Mac.
   - Status: Implemented in Mac source; manual fullscreen QA still needed.
   - Changed: native fullscreen and presentation are separated, and presentation chrome avoids breaking when already in fullscreen.

6. Long landscape PDFs over 20 pages should use simpler speed-based minimap/scroll behavior.
   - Status: Implemented for Mac and Linux minimap dragging; manual large-PDF QA still needed.
   - Changed: long-document drag now scales by document length and pointer speed rather than the old catch-up blend.
   - Changed: fixed the long-document precision-drag regression by preserving horizontal viewport dragging on Mac and Linux, stabilizing the long-document minimap thumb near the bottom, and deferring heavy Mac page/session updates until mouse-up.
   - Changed: Linux precision drag now matches the prompt wording and Mac behavior by activating only for documents with more than 20 pages.
   - Changed: fixed the follow-up minimap overlay regression by drawing the real viewport/page-intersection rectangle again while keeping the stabilized long-document drag math internal.
   - Changed: tuned the long-document drag acceleration curve on Mac and Linux to keep fine adjustment below 180 px/s unchanged while reaching 1:1 speed at 560 px/s instead of 900 px/s.
   - Changed: fixed the follow-up non-continuous regression: Mac single-page mode sizes to the current page instead of the continuous document, so page 1 centers like later pages; Mac minimap uses synthetic full-document coordinates so only the current page's visible slice is highlighted; Linux single-page mode now vertically centers the page box outside continuous mode.
   - Changed: fixed the follow-up Mothership non-continuous page-change regression by making single-page visible-page detection return the current page instead of re-scanning overlapping single-page rects; fixed minimap churn while zooming by suppressing thumbnail render queueing during live zoom and rendering once after zoom settles.
   - Changed: fixed the follow-up Mac single-page scrollbar regression: non-continuous mode again exposes a vertical scrollbar backed by synthetic whole-document height; scrollbar-origin changes now snap straight to page positions so the current page remains centered instead of pixel-scrolling vertically.
   - Tested: installed `/Applications/ShenzhenPDF.app`, cleaned app JSON state with a timestamped backup, opened the Bear Sunny PDF, switched to Single Page with Cmd+4, dragged the document scrollbar from page 2 to page 20, and verified the page jumped directly while remaining centered; Cmd+5 still returns to Continuous mode.
   - Changed: made Fit Page the default zoom for fresh Mac, Linux, and Windows/Sumatra startup state; made long-document minimap viewport dragging more aggressive by keeping fine adjustment at 180 px/s but reaching 1:1 speed at 300 px/s instead of 560 px/s.
   - Tested: built and installed the Mac app, backed up and cleaned app JSON state, opened the Bear Sunny PDF from a fresh state, and verified both Zoom and View menus mark Fit Page by default; built the Linux GTK target successfully; attempted the Windows build on macOS and it failed because VS 2026/msbuild.exe is unavailable in this shell.
   - Changed: ensured fresh Mac tabs opened through Finder/external-open paths start in Fit Page instead of inheriting the active tab's current zoom.
   - Changed: restored the Mac toolbar zoom popup's dynamic custom-zoom row: a remembered non-100% zoom appears above the fixed 100% row and remains available after choosing Fit Page, Fit Width, or Fit Height.
   - Changed: added a Mac tab right-click menu with Show in Folder and Copy; Copy places the tab's file URL on the pasteboard so Finder-style paste copies the PDF file.
   - Tested: rebuilt and installed `/Applications/ShenzhenPDF.app`; user confirmed the custom zoom popup behavior works in the installed app.
   - Changed: stopped the Mac minimap from queuing high-priority full-resolution page renders for minimap-visible placeholders; the minimap now reuses document-view pages when available and fills visible map pages through a separate low-resolution utility thumbnail queue, so the right rail does not stay as blank placeholders and does not block main-page rendering.
   - Changed: routed right-click tab events through the custom titlebar event bridge so the tab context menu appears reliably in the titlebar tab strip.
   - Tested: rebuilt and installed `/Applications/ShenzhenPDF.app`; confirmed there is still exactly one ShenzhenPDF app in `/Applications`; built the Linux GTK target successfully and verified GTK minimap already uses placeholder drawing rather than minimap-triggered full-size renders.

7. Opening a PDF from Finder while the app is in another workspace should switch to the app.
   - Status: Implemented in Mac source; manual Spaces QA still needed.
   - Changed: external open handlers activate/order the target window after opening files.

8. Relaunching should restore split windows promptly in one workspace.
   - Status: Partially treated, not solved.
   - Changed: closing a window removes only that window’s session and suppresses stale rewrite-on-terminate.
   - Changed: direct launch restores stored tabs, and launching with an explicit PDF now restores remembered tabs first, then adds/selects the clicked PDF. Empty windows and tabs without paths are pruned from `session.json`.
   - Changed: external PDF opens are validated before adding tabs, so a corrupt clicked PDF cannot erase or pollute a good previous session.
   - Changed: closing the last app window now saves its tabs before quitting; only non-last windows remove themselves from the stored session.
   - Tested: backed up and cleaned `~/Library/Application Support/ShenzhenPDF/*.json`, then verified clean direct launch, restore-after-quit, cold Finder-style PDF launch restoring Bear plus adding the clicked PDF, empty first-window pruning, corrupt external-open preservation, already-running Finder-open adding to the visible restored session, and red-window-close preserving the last window's documents.
   - Gap: session restore still spawns restored windows as separate processes with `--restore-window`. A full fix should migrate to one-process multi-window controllers.

9. Support default Mac move/resize window shortcuts.
   - Status: Implemented in Mac source; installed-app menu shortcut QA still needed.
   - Changed: the main Mac window now remains movable outside presentation/fullscreen mode, which lets AppKit enable its native Fill, Center, Move & Resize, Full Screen Tile, quarter, arrange, display, and default shortcut handling.
   - Changed: tab-strip and toolbar drag paths now restore the movable state instead of leaving the window non-movable after interaction.
   - Changed: removed the duplicate custom Window-menu Fill/Center/Move & Resize shortcut entries so they no longer conflict with macOS' native Window menu.
   - Changed: added a green-button fullscreen fallback for Control+Fn/Globe+F/C/arrow arrangement shortcuts: the app exits native fullscreen, waits for AppKit's exit callback, then applies the requested Fill, Center, or half-screen frame.
   - Changed: mirrored Fill, Center, and half-window actions under View > Move & Resize Window so they are visible from the menu the user checked.

10. Improve Mac print quality to high DPI.
   - Status: Implemented in Mac source; print-to-PDF visual QA still needed.
   - Changed: PDF files now use PDFKit's native document print operation first, so the original PDF page content is passed to the macOS printing pipeline instead of being pre-rasterized by the app.
   - Changed: PDF print permissions are respected before printing; fallback raster printing remains for non-PDF formats and PDFKit failure cases.
   - Changed: printing now uses `SPDFPrintView` to render pages directly from `spdf_document` at a 1200 DPI target with fallback to lower render zoom and then cached pages.

11. Install and prepare for TestFlight.
   - Status: Local user install completed; TestFlight signing is blocked by missing Apple assets.
   - Installed: `/Applications/ShenzhenPDF.app`.
   - Changed: removed the Mac document-type icon override so Finder/Quick Look can show PDF document previews instead of forcing the Shenzhen PDF app logo on every registered PDF/XPS/CBZ/EPUB file.
   - Changed: set the canonical bundle/app id to `com.intuition.shenzhenpdf`, switched macOS defaults to date-style version `26.6.4-1`, updated TestFlight docs/scripts/package naming, removed the copyright line from the bundle metadata, and added About-panel publisher copy: "Shenzhen PDF is an Open Source app in the spirit of Sumatra PDF, created by Raphaël Casimir, published by Intuition R&T."
   - Gap: TestFlight readiness fails for missing Apple Distribution certificate, 3rd Party Mac Developer Installer certificate, provisioning profile, and Transporter.

12. Tab switching/loading should not reload every PDF on every tab change.
   - Status: Implemented for Mac and Linux; Windows audited as already using persistent per-tab controllers.
   - Changed: Mac tabs now keep resident document/render caches with file mtime/size validation, reuse cached tabs on selection, avoid canceling all inactive preload work on tab switch, and move outline/comment loading off the tab-switch path into cached background work.
   - Changed: Mac inactive preloading is multi-threaded but capped to at most two utility operations, publishes a reusable geometry/document cache before preferred-page rastering, and checks file attributes before reusing the cache.
   - Changed: Linux parks/restores per-tab documents with mtime/size validation so tab selection does not reopen the document when unchanged.
   - Gap: manual stress QA is still needed on many-tab sessions and on Windows because this macOS machine cannot run the Windows app.

13. First launch should feel instant, and tab hover titles must not stick.
   - Status: First low-risk optimization round implemented for Mac and Linux; deeper async first-page rendering remains future work.
   - Plan: paint the Mac window shell before document/session restore, coalesce state writes during startup/open bursts, avoid activating helper restore windows, hide tab hover panels from lifecycle paths that can bypass mouse tracking, and defer Linux sidebar metadata scans out of the attach path.
   - Changed: Mac startup document/session work now runs one main-queue turn after the window is ordered, so the shell can paint before MuPDF open/render starts.
   - Changed: Mac `openPaths` and startup restore batch persistent-state saves, collapsing repeated synchronous JSON/session writes into one final write.
   - Changed: Mac restored helper windows no longer force app activation on launch.
   - Changed: Mac tab hover panels are dismissed when the tab strip is hidden/detached, app/window focus changes, the window resizes/miniaturizes/fullscreens, presentation chrome hides tabs, or tab-strip events become window chrome actions.
   - Changed: Mac minimap thumbnails now render on a separate utility queue so launch/tab-switch visible-page renders are not blocked by the map filling itself.
   - Changed: Mac long-document minimap dragging now explicitly queues high-priority renders for the pages visible in the main viewport while the mouse is still down, forces a tracking-loop repaint, and draws available minimap thumbnails as temporary page previews until full-resolution renders arrive.
   - Changed: Mac now estimates full rendered-page memory at the current zoom; cheap views such as HRO at 37% Retina (~2.08 MB/page, ~244 MB total) and Bear at 37% Retina (~1.08 MB/page, ~38 MB total) pre-render and keep the whole document warm, while expensive zooms such as HRO at 100% Retina (~15.2 MB/page, ~1.78 GB total) keep the bounded cache.
   - Changed: Mac oversized high-zoom pages no longer open a blocking "Rendered page would be too large" alert. Whole-page rastering is skipped when the bitmap would exceed the render guard, and the main viewport renders a full-resolution cropped page region instead.
   - Changed: Mac scroll/minimap-drag/zoom paths render those oversized viewport crops while the mouse is still down, and distant crop images are counted in the render cache so moving through a giant page does not keep unbounded bitmaps.
   - Changed: Mac document panning now suppresses high-resolution oversized crop rerenders during drag/inertia and refreshes the crop once the pan motion settles, fixing max-zoom drag FPS without dropping the final full-resolution viewport.
   - Changed: Mac max-zoom document panning now renders throttled 1x viewport crops during pan/inertia, then refreshes the full backing-scale crop when motion settles; document pan and inertia scrolls explicitly notify the reader, and both single-page and continuous scroll paths call the live crop renderer while pan is active.
   - Changed: Mac live zoom/unzoom now scales the previous high-quality viewport crop instead of falling back to the minimap thumbnail; live zoom no longer performs synchronous crop rendering or full scroll-change normalization on each gesture tick, leaving target-quality rendering until the gesture settles.
   - Changed: Mac tab/document switches now cancel active document pan inertia so motion from one tab cannot carry into the next tab.
   - Changed: Mac empty tab-strip chrome plus passive toolbar labels/spacer support first-click window drag, while toolbar controls and tabs keep normal click/drag handling.
   - Changed: Mac document and minimap interactions now explicitly activate their owning window on first-click drag, so dragging an inactive document or minimap both works immediately and focuses the app.
   - Changed: Mac toolbar page controls now place previous/next to the right of the page field/count, zoom controls now place -/+ to the right of the zoom popup, and zoom overflow keeps the popup plus +/- together.
   - Changed: Mac zoom popup keeps the 100% entry anchored and inserts the custom zoom value after it when distinct, preserving the quick return-to-custom behavior without hiding 100%.
   - Changed: Mac tab strip now captures the whole tab-strip mouse sequence and disables native window movement only while a tab/control mouse sequence is active; passive toolbar drag views temporarily opt into window dragging, protecting tab reorder and drag-out gestures while keeping native window arrangement available.
   - Changed: Mac empty space in the tab row explicitly drags the window again, while expanded tab/control hit zones keep tab reordering and drag-out from being mistaken for window drag.
   - Changed: Mac tab state now writes the latest normalized scroll origin before saving document state JSON.
   - Changed: Mac render queue concurrency now follows the earlier 60% CPU cap, and minimap-drag visible pages promote already-queued background operations instead of waiting behind older low-priority renders.
   - Changed: Mac live zoom no longer runs a synchronous full-document render from the zoom-finish timer; it cancels stale queued page/minimap work when a zoom gesture starts, prevents old-zoom render operations from applying after the zoom changes, suppresses full minimap rebuilds while live zoom is active, and queues visible pages once zoom settles. The user validated that this fixed the reported quick zoom-in then zoom-out input-loss regression.
   - Changed: Mac tab selection no longer saves persistent/session state between switching `_path` to the target tab and restoring that tab's own scroll origin. State is saved after cached and cold tab loads apply the tab's saved viewport, preventing the previous document's clip-view origin from being written into the newly selected tab. The same fix preserves explicit `hasScrollOrigin=false` session entries, suppresses fresh-load viewport relayout until the target tab's origin is restored, and cancels pending live-zoom settle timers when switching/closing documents. The user validated that document positions no longer appear to cross-affect each other.
   - Changed: Mac windows are movable again in their resting state so AppKit can enable native Fill, Center, Move & Resize, Full Screen Tile, and their default shortcuts; tab-strip gestures still force `movable` off until mouse-up so tab reordering and drag-out stay protected. The user validated that window-management shortcuts work again.
   - Changed: Mac high-zoom live zoom now skips no-op ticks at the zoom cap before doing anchor/geometry work, uses a lightweight resize path during the gesture instead of retile/layout/minimap/find invalidation on every wheel tick, suppresses scroll callbacks while preserving the zoom anchor, throttles toolbar refreshes, and repaints only the current viewport. `SPDFDocumentView` also fills only the dirty rectangle instead of the full enormous high-zoom document bounds. When live zoom settles, the app now renders the visible viewport crop synchronously before queueing full/nearby page renders, so the visible document crisps up immediately instead of waiting behind background work. The user validated that high-zoom zooming is responsive again and no longer stays blurry after settling.
   - Changed: Linux `attach_document_to_view` always schedules the existing deferred sidebar metadata load instead of synchronously loading outline/comments before tab-switch paint.
   - TODO: investigate rare Mac tab switches where restored document position appears influenced by the previous tab's viewport even after the scroll-origin save-order fix.
   - Gap: next performance round should move Mac and Linux first-page rastering off the launch/tab-switch foreground path and build exact long-document geometry lazily.

14. Prepare `26.6.4-2` launch-performance round without behavior changes.
   - Status: First strict behavior-preserving Mac reductions implemented.
   - Constraint: no visual or behavioral changes. Do not change render/loading resolution, first visible document quality, restored documents/tabs, active tab selection, scroll position, sidebar/minimap semantics, or file/session persistence semantics.
   - Process: reread this journal before decisions; collect read-only agent reports first; classify options as safe/medium/risky; implement only safe changes that remove redundant blocking work or move already-deferred work later without changing user-visible output.
   - Candidate-safe areas to investigate: redundant synchronous state writes during startup/open, work duplicated between startup restore and tab selection, avoidable post-first-paint background scheduling before the first window visibly settles, and cross-platform equivalents that preserve exact visual behavior.
   - Changed: `SPDFDocumentView` now caches exact snapped page sizes, widest-page width, continuous page rectangles, continuous document height, and synthetic single-page slots. The cache is invalidated on pages, zoom, view mode, presentation mode, backing scale, viewport width, and view bounds; live single-page centering still reads the current clip-view bounds.
   - Changed: `SPDFMinimapView` now caches the exact unscrolled mini page rectangles for the current pages, bounds width, scale, and gap. Minimap overlay, drag, hit-test, and click math continue to use the same geometry formulas.
   - Changed: identical delayed nearby-render schedules for the same delegate, generation, path, and preferred page are coalesced until the delayed request fires; page render order, priority, resolution, and eventual queueing stay unchanged.
   - Changed: max-zoom document panning no longer renders live viewport crops synchronously on the main drag path. A single generation-guarded utility background crop job updates the preview when ready, stale crop jobs are ignored across new pans/tabs/zooms, live-zoom settle re-arms itself while a pan is active instead of running final layout/render work mid-drag, and image cache eviction is deferred until pan finish.
   - Tested: ran explicit ObjC-style clang-format on touched Mac `.mm` edits, `git diff --check`, ObjC++ syntax for `SPDFMacDocumentView.mm`, `SPDFMacMinimapView.mm`, and `ShenzhenPDFMac.mm`, `make -C portable mac-app`, and `./dist/ShenzhenPDF.app/Contents/MacOS/ShenzhenPDF --version`.

15. First-launch default PDF reader prompt and print scaling controls.
   - Status: Implemented for Mac; pending manual validation before commit.
   - Changed: added a first-launch prompt to make Shenzhen PDF the default PDF reader, persisted dismissal in `settings.json`, and added a File menu command to retrigger the same flow at any time.
   - Changed: added LaunchServices default-reader helpers using the app bundle id and the PDF UTI.
   - Changed: added print scaling controls as an accessory inside the macOS print panel itself, so the user sees Shenzhen PDF scaling next to the normal printer options and the panel's real page preview. PDF printing uses a PDFKit page-drawing print view for fit, actual-size, and custom scaling; non-PDF/fallback printing keeps the 1200 DPI bitmap renderer and now honors the same scaling modes.
   - Changed: enabled the system Paper Size and Orientation controls in the macOS print panel. The options are seeded by AppKit from the selected/default printer, and the Shenzhen PDF print views resize their page frame from the current `NSPrintInfo` so the real preview/output follows the selected target sheet.
   - Constraint: bitmap output remains fallback-only for PDF printing unless PDFKit/native printing cannot be used.
   - Tested: ran explicit ObjC-style clang-format on touched Mac files, `git diff --check`, `make -C portable mac-app`, `make -C portable install`, `/Applications/ShenzhenPDF.app/Contents/MacOS/ShenzhenPDF --version`, installed app codesign verification, `/Applications` uniqueness check, and `make -C portable linux`.

16. Prepare `26.6.5-1` for TestFlight validation.
   - Status: Implemented; commit and tag requested by user.
   - Changed: bumped macOS bundle defaults to App Store-compatible `CFBundleShortVersionString=26.6.5` and `CFBundleVersion=1`, with About/CLI display as `26.6.5-1`.
   - Changed: updated TestFlight build defaults and handoff docs to produce `ShenzhenPDF-testflight-26.6.5-1.pkg`.
   - Tested: rebuilt and installed `/Applications/ShenzhenPDF.app`; verified CLI version `26.6.5-1`, bundle short version `26.6.5`, bundle build `1`, bundle id `com.intuition.shenzhenpdf`, codesign, `/Applications` uniqueness, `git diff --check`, and Linux build. TestFlight readiness has build tools/OpenSSL/MuPDF OK and still requires Apple Distribution certificate, 3rd Party Mac Developer Installer certificate, provisioning profile, and optionally Transporter.

17. Command palette result display and tab-strip drag regression.
   - Status: Implemented; pending manual validation before amending the `26.6.5-1` commit.
   - Changed: open-document text-search results now show `<tab title> - page x : y matches` on the first line, with only the tab title bolded, and keep the second line as compact context snippets with bolded matches.
   - Changed: Mac tab gestures now use an expanded interaction rect across the tab row height for each visible tab, and the window is non-movable in its resting state so AppKit cannot steal tab gestures as titlebar drags. True empty tab-row space and passive chrome still perform explicit temporary window drags.
   - Changed: Mac app-owned Window menu arrangement entries and Ctrl+Fn Fill/Center/Half shortcuts now work in normal windows as well as fullscreen; the Window menu temporarily enables window movability while open so macOS can still validate its own native arrangement items, then restores the non-movable resting state when closed.
   - Changed: Mac single-page mode now treats left-drag as document panning. Pages that fit vertically remain centered and vertical drag/page scroll changes pages; zoomed pages taller than the viewport keep a stable page rect and clamp inside the page so dragging moves through the enlarged document instead of snapping back to center.
   - Changed: Mac active document panning now keeps gesture ticks lightweight by repainting the viewport immediately while coalescing minimap updates and live crop rendering behind one scheduled maintenance callback. Final full-resolution crop rendering still runs when pan motion finishes.
   - Changed: Mac single-page/non-continuous drag now disables release inertia entirely so slides do not vibrate after the user lets go.
   - Changed: Mac scroll-wheel page changes now ignore Command, Control, and Option modified events, while modified wheel zoom events are consumed by the scroll view and immediate post-zoom phase/momentum or very-near follow-up wheel ticks are dropped so zoom gestures cannot also flip/scroll pages.
   - Changed: Mac live zoom now keeps one stable page anchor for the duration of the wheel/magnify gesture, preventing continuous-mode zoom ticks from drifting the document slightly downward.
   - Constraint: do not commit/amend until the user manually validates the tab detach/window-drag behavior.

18. `26.6.5-2` launch should be static and faster without visual compromise.
   - Status: Implementation started; commit step by step after each validated slice.
   - Constraint: preserve first visible document quality, restored tabs, restored position, sidebar/minimap semantics, tab order, and Finder/session behavior. No low-resolution first paint or visible layout mutation as a launch shortcut.
   - Changed: Mac startup document/session work now runs before the main window is ordered, so the first visible frame already has the selected tab, document, sidebar, minimap, and restored scroll state applied. Default-reader and shortcut-help prompts remain deferred until after the window is visible.
   - Changed: added a core page-size cache seeding API and a Mac exact page-geometry cache in `documents.json`. After a document has completed exact all-page layout once, later launches/openings validate file size, modified date, page count, and all page dimensions before seeding MuPDF's in-memory page-size cache, avoiding synchronous load/bounds of every page while preserving exact layout.
   - Changed: Mac launch now loads the selected document's outline/comments before ordering the first window when the sidebar is meant to be visible, so the left panel does not collapse or appear after the first visible frame. Normal tab switching keeps the deferred metadata path.
   - Changed: Mac single-page/non-continuous live zoom now preserves the active page and live-zoom anchor through the final resize pass, suppressing synthetic scrollbar callbacks so Command-scroll zoom cannot be interpreted as a page-changing scroll.
   - Changed: Mac continuous-mode live zoom now uses a centered page anchor when the current page is fully visible, avoiding the slight downward scroll drift while zooming/unzooming at fit-page-like sizes. Mac single-page drag/page-turn detection now uses an explicit one-third-viewport threshold instead of waiting for the synthetic page slot overlap to dominate.
   - Next: validate launch behavior on restored/recent long PDFs, then consider diagnostics and deeper post-first-paint staging if Preview is still noticeably ahead.

19. Prepare `26.6.7-1` for TestFlight validation.
   - Status: Implemented; commit and tag requested by user.
   - Changed: bumped macOS bundle defaults to App Store-compatible `CFBundleShortVersionString=26.6.7` and `CFBundleVersion=1`, with About/CLI display as `26.6.7-1`.
   - Changed: updated TestFlight build defaults and handoff docs to produce `ShenzhenPDF-testflight-26.6.7-1.pkg`.
   - Constraint: keep previous release journal entries historically intact; only current build defaults and handoff references move to today's version.
   - Tested: ran ObjC-style clang-format on the touched Mac fallback lines, `git diff --check`, `make -C portable mac-app`, `make -C portable install`, installed CLI version check, installed bundle id/short-version/build checks, installed app codesign verification, `/Applications` app-name check, `./portable/check-testflight-ready.sh`, `make -C portable linux`, and `portable/build/ShenzhenPDF-gtk --version`.
   - Gap: TestFlight readiness still requires the Apple Distribution certificate, 3rd Party Mac Developer Installer certificate, App Store provisioning profile, and optionally Transporter. A hidden root-owned `/Applications/.ShenzhenPDF.app.old-20260603-122602` backup could not be removed by the unprivileged cleanup command; `/Applications/ShenzhenPDF.app` is the current installed app.

20. Non-continuous drag/page-turn state cleanup.
   - Status: User validated; committed in `167c0bce0`.
   - Agent findings: stale single-page pan baselines could survive a page snap, wheel-page accumulators could carry sub-threshold deltas or momentum across gestures, pinch zoom did not clear wheel page-turn state, and pending live-zoom timers could restore pre-navigation anchors.
   - Changed: rebase single-page mouse-drag state after a drag-induced page snap, turn wheel page changes into one-shot gestures that ignore momentum and reset on begin/end/direction/timeout, clear wheel state for pinch zoom, cancel pending live-zoom completion before page navigation or document panning, defer single-page snap-back until pan release unless a page actually changed, and restore continuous-mode left-drag entry into document panning when the document has scrollable content.
   - Validation target: in non-continuous mode, dragging beyond the threshold should move exactly one slide per drag segment, release should have no inertia/vibration, Cmd/Ctrl zoom should not queue page changes, and dragging immediately after zoom should not feel blocked.

21. Default PDF reader double-click regression.
   - Status: Implemented and committed in `167c0bce0`; direct double-click behavior remains a manual Finder validation item.
   - Root cause: the previous default-reader helper only set LaunchServices' PDF viewer role. Finder's Get Info showed Shenzhen PDF, but the all/editor role used by double-click could remain `com.apple.Preview`.
   - Changed: declare PDF as its own explicit `com.adobe.pdf` document type, set viewer/editor/all roles through LaunchServices, and fall back to repairing the user's `LSHandlers` row plus refreshing `lsd` when macOS returns success but leaves Preview in the all-role slot.
   - Tested: reproduced the broken `viewer=Shenzhen, all/editor=Preview` state, ran the helper harness, verified a fresh LaunchServices query reports viewer/editor/all as `com.intuition.shenzhenpdf`, rebuilt/installed `/Applications/ShenzhenPDF.app`, and confirmed `open /Users/raph/Downloads/Bear Sunny Technologies Inc for Blackstar.pdf` opens Shenzhen PDF without launching Preview.app.

22. GNOME-style document search sidebar.
   - Status: User validated; included in the `26.6.8-1` release commit.
   - Prompt link: when the user searches, a new sidebar tab like Chapters/Comments should appear, switch to immediately, list contextual search results, and insert visually distinct chapter separators.
   - Agent findings: product acceptance criteria require current-document-only results, exact-match jumps, non-clickable divider/status rows, result selection syncing with next/previous find navigation, graceful no-result/searching states, and no stale rows after clearing or switching documents.
   - Changed: Mac sidebar mode now dynamically adds a Search segment only while search state exists, opens/switches the sidebar when a query starts, builds result rows from `_findMatches` with page/match subtitles and extracted text snippets, groups results under chapter dividers, keeps Search selection synced to `_findMatchIndex`, and routes result clicks through `jumpToFindMatchAtIndex:`.
   - Review fixes: changed divider rows to adaptive left-aligned muted capsule chapter labels that only draw a right-side rule when there is meaningful leftover space, made status/divider rows non-navigable, dynamically clamps sidebar width so three segments fit, keeps result rows single-line truncated instead of wrapped, and bolds literal query matches in result context text.
   - Validation target: type a search, confirm Search appears and is selected, results show useful single-line snippets grouped by chapter, clicking a result jumps and flashes the exact match, next/previous updates the selected result, no-result/searching rows do not navigate, and clearing search removes Search without breaking Chapters/Comments.

23. Mac window arrangement shortcut regression.
   - Status: User validated; included in the `26.6.8-1` release commit.
   - Prompt link: the Window/View menu actions still work, but their keyboard shortcuts regressed, so the keyboard dispatch path needs a test and fix.
   - Changed: extracted Mac window-arrangement shortcut matching into `SPDFMacWindowShortcuts`, installed a local key monitor so Ctrl+Fn/Globe window shortcuts are handled before AppKit menu-key dispatch can swallow them, accepts missing Fn/NumericPad flags as a fallback outside text editing, and kept the existing `SPDFWindow` send-event fallback.
   - Changed: added `make -C portable mac-window-shortcut-tests`, covering Ctrl+Fn/Globe Fill/Center, Ctrl+Fn/Globe arrows, Fn-arrow translations to Home/End/PageUp/PageDown, AppKit numeric-pad arrow events, missing-flag fallback events, selector routing, and modified-key rejection.
   - Validation target: with the installed app focused, Ctrl+Fn/Globe+F fills, Ctrl+Fn/Globe+C centers, Ctrl+Fn/Globe+Left/Right/Up/Down move to halves, and clicking the menu items continues to work.

24. Mac window resize smoothness and corner hit-testing.
   - Status: User validated; included in the `26.6.8-1` release commit.
   - Prompt link: resizing lagged badly, and the top-right resize corner often started a window drag instead of a resize.
   - Changed: live window resize now uses a lightweight relayout path that scales cached page imagery, skips full-resolution crop rendering, avoids minimap thumbnail queueing, avoids repeated persistent-state writes, and performs the full viewport/fit render once when resizing ends.
   - Changed: top chrome drag now reserves a small 16 px resize zone in the top corners so AppKit can receive corner resize gestures while the rest of the empty top chrome still drags the window.
   - Validation target: resize the app from corners and edges with Bear Sunny/HRO open; resizing should feel much smoother, top-right corner should consistently resize, and dragging empty tab/chrome space should still move the window.

25. Mac trackpad pan direction stickiness.
   - Status: User validated; included in the `26.6.8-1` release commit.
   - Prompt link: two-finger trackpad movement felt directionally sticky compared with Preview, requiring extra movement to switch from horizontal to vertical motion or back.
   - Changed: disabled AppKit predominant-axis scrolling on the document scroll view and explicitly allowed horizontal/vertical scroll elasticity, so precise trackpad deltas can flow as free 2D panning while existing zoom and non-continuous page-turn handling stays in place.
   - Validation target: with a zoomed document wider and taller than the viewport, two-finger pan horizontally, vertically, diagonally, and change direction quickly; movement should follow the fingers with much less axis locking.

26. Mac defaults for side panel and map on new documents.
   - Status: Implemented; included in the `26.6.8-1` release commit.
   - Prompt link: add General/Settings controls for whether new documents open with the side panel and map visible, defaulting to the current behavior of visible.
   - Agent finding: global visibility defaults did not exist; current app stores per-tab/session and per-document `showSidebar`/`showMinimap`, and new tabs hardcoded both to `YES` before applying remembered document state.
   - Changed: added `settings.json` keys `defaultSidebarVisibleForNewDocuments` and `defaultMinimapVisibleForNewDocuments`, both defaulting to `YES`.
   - Changed: added checkable Settings menu items for “Open New Documents with Side Panel” and “Open New Documents with Map”; toggling saves immediately and affects future tabs only.
   - Changed: new tabs and legacy session entries without saved visibility use the global defaults first, then existing remembered per-document state still wins.
   - Validation target: defaults are checked on a clean profile, unchecking one or both writes `settings.json`, newly opened never-seen PDFs follow the chosen defaults, and previously opened PDFs keep their remembered visibility.

27. Mac trackpad fast-swipe acceleration.
   - Status: User validated; included in the `26.6.8-1` release commit.
   - Prompt link: after free 2D trackpad panning felt good, fast two-finger swipes accelerated too aggressively to the first/last page.
   - Changed: precise trackpad scroll events now use a high-speed damping curve in `SPDFScrollView` after zoom/page-turn handling; slow/fine deltas remain effectively unchanged, while large and momentum deltas are compressed before moving the document clip view.
   - Constraint: mouse-wheel scrolling, Command/Control zoom gestures, and non-continuous page-turn conversion are left on their existing paths.
   - Validation target: fast two-finger swipes should still coast, but no longer jump violently to the beginning/end; slow two-finger panning should retain the improved Preview-like free movement.

28. Continuous Fit Page scroll behavior.
   - Status: User validated; included in the `26.6.8-1` release commit.
   - Prompt link: fitting the page in continuous mode made scrolling act like non-continuous mode, jumping one page at a time.
   - Root cause: wheel-to-page-turn conversion was keyed on `Fit Height`/`Fit Page` even when `_viewMode` was continuous.
   - Changed: only single-page view converts wheel/trackpad scrolling into page changes; continuous mode keeps normal continuous scrolling for every zoom/fit mode.
   - Validation target: in continuous mode, choose Fit Page and scroll with the trackpad/wheel; the document should move continuously instead of stepping page by page. Non-continuous mode should still page-turn as before.

29. Single-page PDF map default.
   - Status: User validated; included in the `26.6.8-1` release commit.
   - Prompt link: when a single-page PDF is opened, override the default map display option and hide the map by default, while still allowing the map to be opened manually.
   - Changed: tabs now track whether minimap visibility came from explicit saved/session state versus a default. After a document loads and page count is known, one-page documents with no explicit minimap preference default to hidden regardless of the global new-document map setting.
   - Constraint: user/session/document-state choices still win. If the map was explicitly shown for that one-page file, it can persist normally.
   - Validation target: open a never-seen one-page PDF with the global map default enabled; the map should be hidden. Toggle Map on, reopen or switch away/back, and it should remain allowed/restored.

30. Prepare `26.6.8-1` for TestFlight validation.
   - Status: Implemented and validated for the `26.6.8-1` release commit.
   - Prompt link: after validating the recent Mac behavior fixes, update the About/version metadata to today's version, prepare TestFlight, commit, and tag.
   - Changed: bumped macOS bundle defaults to App Store-compatible `CFBundleShortVersionString=26.6.8` and `CFBundleVersion=1`, with About/CLI display as `26.6.8-1`.
   - Changed: updated TestFlight helper defaults, package naming docs, and release references to produce `ShenzhenPDF-testflight-26.6.8-1.pkg`.
   - Tested: rebuilt and installed `/Applications/ShenzhenPDF.app`; verified CLI version `26.6.8-1`, bundle metadata `com.intuition.shenzhenpdf`/`26.6.8`/`1`, local codesign, Objective-C++ syntax, shortcut tests, and diff hygiene.
   - Gap: TestFlight readiness has build tools/OpenSSL/MuPDF OK but still requires Apple Distribution certificate, 3rd Party Mac Developer Installer certificate, App Store provisioning profile, and optionally Transporter before a signed upload `.pkg` can be produced.

31. Prepare `26.6.8-2` post-zoom responsiveness release.
   - Status: Implemented; committed and tagged as `26.6.8-2`.
   - Prompt link: after live zoom became fluent, the user reported an unacceptable 2-500 ms freeze immediately after zooming, plus a missing minimap viewport preview during zoom. README should also be refreshed to showcase the reader before TestFlight prep.
   - Agent prompt rewrite: priority is immediate post-zoom pan/scroll responsiveness while preserving the fluent zoom/pan strategy; minimap during-zoom viewport preview is desirable only if it does not reintroduce stutter.
   - Changed: live-zoom settle no longer renders the crisp backing-scale viewport crop synchronously on the main thread. It queues a high-priority async viewport crop, invalidates stale crop results when newer movement or sync rendering happens, and gives throttled requests a delayed retry so the latest viewport is not lost.
   - Changed: minimap updates now refresh lightweight geometry and viewport state during live zoom while still skipping minimap thumbnail/render work until zoom settles.
   - Changed: README and portable README were rewritten to describe Shenzhen PDF's core reader features, macOS/Linux portable frontends, search/minimap/OCR/translation/windowing polish, current boundaries, and TestFlight handoff.
   - Changed: bumped macOS bundle build to App Store-compatible `CFBundleVersion=2`, keeping `CFBundleShortVersionString=26.6.8`, with About/CLI display as `26.6.8-2`.
   - Changed: updated TestFlight helper defaults and docs to produce `ShenzhenPDF-testflight-26.6.8-2.pkg`.
   - Reviewed: agent review found and the implementation fixed stale async crop application, dropped throttled crop requests, full-page render priority ahead of viewport crops, in-flight stale crop loops, live-zoom minimap O(n^2) geometry work, and pan-begin crop invalidation.
   - Tested: rebuilt and installed `/Applications/ShenzhenPDF.app`; verified CLI version `26.6.8-2`, bundle metadata `com.intuition.shenzhenpdf`/`26.6.8`/`2`, local codesign, Objective-C++ syntax, shortcut tests, and diff hygiene.
   - Gap: TestFlight readiness has build tools/OpenSSL/MuPDF OK but still requires Apple Distribution certificate, 3rd Party Mac Developer Installer certificate, App Store provisioning profile, and optionally Transporter before a signed upload `.pkg` can be produced.

32. High-zoom drag regression after `26.6.8-2`.
   - Status: Implemented for manual validation; not committed.
   - Prompt link: moving inside the document became laggy at relatively high zoom; check whether it is better to revert the latest async crop changes and keep only a zoom-to-drag transition fix.
   - Finding: the async post-zoom viewport crop queue added in `26.6.8-2` is the likely regression source because it can compete with high-zoom pan rendering on the shared render queue right when the user starts dragging.
   - Changed: removed the async viewport-crop queue, retry throttle, and grace window, restoring the `26.6.8-1` synchronous crop path for normal pan/minimap behavior.
   - Changed: replaced the immediate post-zoom crisp crop with a short delayed render guarded by document path, render generation, live-zoom sequence, and viewport-movement generation. If the user begins dragging or trackpad-scrolling after zoom, the delayed crop cancels instead of stealing responsiveness.
   - Kept: lightweight minimap viewport updates during live zoom, since they avoid thumbnail work and were not tied to the high-zoom drag lag.
   - Validation target: at high zoom, dragging inside Bear Sunny and the long document should feel like the validated `26.6.8-1` movement path. Zoom-to-drag should no longer freeze; if dragging starts immediately after zoom, the crisp crop may wait until movement settles.

33. Search sidebar panel cleanup.
   - Status: Implemented for manual validation; not committed.
   - Prompt link: the Search sidebar tab should not show the redundant disabled “Search Results” filter box, and the “No matches...” empty state should be visually centered.
   - Changed: the sidebar filter field is now hidden only while the Search segment is active, and the results scroll view moves directly below the segmented control. Chapters and Comments keep their existing filter field behavior.
   - Changed: search status rows use the visible search-results height so the centered label is actually centered in the panel, not in a short table row at the top.
   - Validation target: search with no matches should show no in-panel search box and center the “No matches for ...” text in the available Search panel area.

34. Restore text selection priority over page drag.
   - Status: Implemented for manual validation; not committed.
   - Prompt link: text became unselectable because primary left-drag on the PDF page started document panning instead of text selection.
   - Finding: the Mac document view was checking “can this document pan?” before starting selection, so any zoomed or single-page document swallowed left-drag selection.
   - Changed: primary left-drag on a page now starts as text selection. If the drag moves past a small threshold and still selects no text, the interaction falls back to document panning from the original mouse-down point.
   - Preserved: page-margin/blank-page dragging, right-drag, middle/other-button drag, trackpad panning, and single-page pan/page-turn behavior remain available.
   - Validation target: dragging over selectable text should select/copy text; dragging blank slide/page areas should still move the document where panning is available.

35. Save As fallback for protected PDFs.
   - Status: Implemented, installed, and ready for user validation.
   - Prompt link: Cmd/Ctrl+S should expose Save As, File should include Save As, and operations that need to write back to a read-only or temporary PDF should offer Save As instead of failing.
   - Changed: macOS adds File > Save As... on Cmd+S and saves the active PDF through `NSSavePanel`, then updates the tab path, cached document state, recent documents, and persistent state.
   - Changed: macOS preflights PDF mutations before rotate, OCR, translation, and comment add/edit/delete. If the current PDF is in a temp folder or the file/folder is not writable, Shenzhen PDF asks for a writable copy and continues only if Save As succeeds.
   - Changed: Linux mirrors File > Save As... on Ctrl+S, saves through a GTK save dialog, retargets the active tab to the saved PDF in place, and preflights rotate, OCR, translation, and comment add/edit/delete with the same writable/non-temp requirement.
   - Validation target: open a PDF from `/tmp` or a read-only folder, run rotate/OCR/translate/comment edit, and verify the Save As prompt appears before the operation writes back.

36. Stop left-click panning and stabilize trackpad live-zoom minimap preview.
   - Status: Partially reverted for manual validation; not committed.
   - Prompt link: after zoom-to-drag responsiveness improved, trackpad zoom still felt slightly laggy, the minimap viewport preview drifted during zoom, and left-click still dragged when clicking between text.
   - Changed: primary left-drag on the document surface is selection-only. It no longer falls back to document panning on blank text gaps or page whitespace. Right/middle-button panning and trackpad scrolling remain separate paths.
   - Reverted: the live-zoom minimap page-rect refresh and center-anchored trackpad pinch were rolled back after they made the drag/zoom behavior worse. Trackpad magnify again uses the event window point, and live zoom no longer rebuilds minimap page geometry mid-gesture.
   - Validation target: drag between words/lines with left click should select or do nothing, never pan; trackpad zoom/drag should return to the previously better feel without the new minimap drift.

37. Restore OCR output integrity.
   - Status: Implemented for validation; not committed.
   - Prompt link: OCR appears to run successfully, but after completion no selectable text is produced in the document.
   - Finding: direct OCRmyPDF runs on controlled no-text PDFs do produce selectable text, so the app boundary needed to stop trusting process success as document success.
   - Changed: macOS and Linux now run the image-only path without `--skip-text`, validate the produced PDF with the core text extractor before replacing the original, and leave the original file unchanged if validation fails.
   - Changed: if an image-only PDF still validates as no-text after the normal OCR pass, the app retries once with OCRmyPDF's forced image OCR mode, then validates again before installing the result.
   - Validation target: OCR a no-text scanned/image PDF; after the app reports completion, text selection/search should work in the reloaded document. If OCRmyPDF completes but produces no selectable text, Shenzhen PDF should show an error instead of replacing the original.

38. Revert last drag/zoom tweak.
   - Status: Implemented for manual validation; not committed.
   - Prompt link: the last modification to the drag/zoom issue made the behavior worse and should be reverted.
   - Changed: removed the trackpad pinch center-anchor helper and restored `magnifyWithEvent:` to pass `event.locationInWindow`.
   - Changed: removed the live-zoom minimap page-rectangle rebuild added in the previous tweak; during live zoom the minimap updates only the lightweight viewport fields as before.
   - Preserved: OCR output validation, Save As fallback work, and text-selection-only left-click behavior were left intact.
   - Validation target: compare trackpad zoom/drag against the previous better feel; the new worsening drift/stickiness should be gone.

39. Stabilize page rotation reload state.
   - Status: Implemented for validation; not committed.
   - Prompt link: page rotation reloads incorrectly, the displayed page state does not always match the saved PDF, and sometimes a second page rotates; only the current page shown in the page counter should turn.
   - Finding: the core rotation function rotates exactly one page object in a controlled `qpdf` smoke test, but macOS render worker threads cached opened PDFs by path only, so after saving a rotation they could continue rendering the pre-rotation file.
   - Finding: after a rotation save, the selected tab kept its old absolute scroll origin. Because rotation changes page geometry, reload could land on a neighboring page, so a repeated rotate could affect a different page than the one the user meant.
   - Changed: macOS worker PDF caches are keyed by standardized path, file size, and modification date, forcing render workers to reopen a changed PDF after rotation/OCR/Save As-style writes.
   - Changed: macOS rotation reads the current page from the visible page counter, cancels transient pan/zoom state, clears the tab scroll origin, and reloads explicitly to that page index after saving.
   - Validation target: rotate page N, verify the app reloads still on page N, only page N changes in the saved PDF, and a second rotation without changing the page rotates page N again rather than a neighbor.

40. Passive inactive-window scrolling and zooming.
   - Status: Implemented for validation; not committed.
   - Prompt link: if the mouse is over the app and the app is not focused, scrolling and zooming should work without focusing the app until a click is detected.
   - Finding: the main document scroll view already handled wheel and magnify events without calling the window activation helper, but the minimap wheel and magnify handlers activated the app before forwarding scroll/zoom.
   - Changed: minimap scroll-wheel zoom, minimap pinch zoom, and minimap wheel scrolling now forward passive events without activating the app. Minimap click/drag still activates through `mouseDown`, preserving the current click behavior.
   - Validation target: make another app active, hover the document and minimap in Shenzhen PDF, scroll and pinch/Cmd-scroll; the document should move/zoom while Shenzhen PDF remains inactive until an actual click.

41. Copy Path menu commands and menu icons.
   - Status: Implemented for validation; not committed.
   - Prompt link: add Copy Path to the document right-click menu and tab right-click menu, and try to put relevant system icons in front of menu options, including top menus.
   - Changed: macOS File, document context, and tab context menus now expose Copy Path, copying the active/tab PDF path as plain text while keeping the existing tab Copy command as a file pasteboard copy.
   - Changed: macOS menu items receive SF Symbol icons by action/title across top-level menus and context menus where symbols are available on the host system.
   - Changed: Linux File and document context menus expose Copy Path, Linux tab right-click now exposes Show in Folder and Copy Path, and icon-capable GTK menu items use standard theme icon names where the desktop renders menu icons.
   - Validation target: Copy Path from File, document right-click, and tab right-click should place the exact document path on the clipboard; existing Copy should still copy the PDF file object on macOS tabs; menu icons should appear where the OS/theme allows them.

42. Restore live-zoom minimap viewport geometry only.
   - Status: Implemented for validation; not committed.
   - Prompt link: zoom now feels like the previous acceptable behavior, but the minimap viewport behavior should keep the earlier good fix.
   - Finding: after reverting the worsening zoom-anchor changes, live zoom still updated the minimap visible rectangle and scale but no longer refreshed the per-page document rectangles used to project that viewport onto the minimap. That left the blue viewport overlay calculated against stale page geometry during zoom.
   - Changed: live zoom now refreshes only `documentPageRects` for the minimap before drawing the viewport overlay. It still avoids resetting minimap pages and skips thumbnail rendering while zooming, so the zoom gesture behavior and thumbnail performance strategy remain unchanged.
   - Validation target: during fast zoom in/out, the minimap viewport should stay aligned with the actual visible document area without reintroducing the previous trackpad zoom/drag regression.

43. Search sidebar layout polish.
   - Status: Implemented for validation; not committed.
   - Prompt link: no-match text is still not centered, search result text should align with the beginning of the “Chapters” segment label, chapter pills should extend farther right, and result text should truncate with ellipses according to panel width.
   - Changed: search result rows and chapter divider pills use a dedicated left edge, matching the segmented-control text line more closely than the generic sidebar row inset.
   - Changed: the sidebar table column now tracks the visible scroll-view width on rebuild and sidebar resize, so result titles/subtitles truncate against the current panel width.
   - Changed: empty/search-status rows refresh their height and reset scroll position when search results disappear, so the “No matches...” message centers in the visible Search panel instead of inheriting the previous result-list scroll offset.
   - Changed: chapter divider pills expand to the available row width when there is no room for a useful trailing line; highlighted result titles carry a truncating paragraph style so they end with ellipses instead of clipping or wrapping.
   - Validation target: search for no matches and verify the message is visually centered; search for matches and verify divider pills/results start at the same left edge as the “Chapters” label and truncate cleanly while resizing the side panel.

44. Live minimap FPS after accurate viewport geometry.
   - Status: Implemented for validation; not committed.
   - Prompt link: the minimap viewport position is now accurate, but the minimap itself runs around 5 fps while the rest of the app remains smooth.
   - Finding: the accurate live-zoom path recalculates the viewport overlay correctly, but each minimap repaint still redraws every visible thumbnail, highlight, selection, and current-page border before drawing the blue viewport rectangle.
   - Changed: `SPDFMinimapView` now builds a bounded offscreen thumbnail-strip cache during live viewport updates and reuses it while the accurate viewport overlay moves. Normal minimap redraws still invalidate the cache, so search highlights, selections, page changes, and newly rendered thumbnails do not stay stale outside the live path.
   - Changed: the controller enables this cache only while `_liveZooming` is true. The existing accurate `documentPageRects` and `documentVisibleRect` updates remain unchanged.
   - Validation target: zoom/drag a long document with the minimap open; the blue viewport should remain aligned with the visible document area while the minimap updates fluidly, without changing normal thumbnail resolution after zoom settles.

45. Side-panel resize hit target.
   - Status: Implemented for validation; not committed.
   - Prompt link: the side panel resize click target is too small and nearly impossible to grab; the minimap divider was already correct and should not be changed.
   - Changed: the left side-panel `NSSplitView` now advertises an 18 pt effective divider hit rectangle while keeping the thin visual divider and all existing sidebar width constraints.
   - Preserved: the minimap divider remains the separate `SPDFMinimapDividerView` with its existing width and drag behavior unchanged.
   - Validation target: with the side panel open, grabbing near the vertical split between sidebar and document should resize reliably; the minimap divider should feel exactly as before.

46. Restore top-menu text and protect Find-field navigation.
   - Status: Implemented for validation; not committed.
   - Prompt link: top menu names should be plain text; icons belong only inside menu contents. Long Find-field text should be navigable with arrow keys and mouse like a standard macOS text field.
   - Finding: the menu icon helper was applied to `NSApp.mainMenu` itself, so it decorated the top-level menu bar items. It should instead recurse into each top-level submenu.
   - Finding: an explorer agent confirmed the main Find field is a stock `NSSearchField`; the likely shortcut conflict was the window-arrangement key path bypassing the text-editing guard when Function-style arrows were pressed.
   - Changed: top-level menu bar items are no longer assigned SF Symbol icons. Icons still apply inside File/View/Window/etc. menus and nested menu contents.
   - Changed: the toolbar Find field now uses `SPDFFindSearchField`, a tiny subclass that accepts first mouse and cannot become a window-drag region.
   - Changed: document arrow navigation and window-arrangement shortcuts now always yield while any text field/editor is active, and window-arrangement menu key equivalents validate disabled during text editing.
   - Validation target: menu bar should show text-only top menu names; inside opened menus icons should remain. Paste a Find query longer than the field, then verify mouse clicks and Left/Right, Option-Left/Right, Command-Left/Right, and Fn/Home/End-style navigation move within the field without scrolling pages or moving/resizing the window.

47. Selected-text browser search and editable selection translation.
   - Status: Implemented for validation; not committed.
   - Prompt link: add a Preview-like selected-text Search in Browser action, and add local selection translation without asking language first; remember languages, show source/target dropdowns, editable input/output, and retranslate on demand.
   - Agent prompt rewrite: selected text should gain context actions that are lazy, fast, and non-blocking: macOS should use the system/default browser search route rather than hardcoded Google, and translation should reuse the existing local Argos backend only when invoked.
   - Finding: the portable Mac app already stores selected text in `_selectedText` and already has Argos Translate support for document/selection-to-PDF translation with persisted source/target language codes.
   - Changed: the document context menu now shows `Translate "<selection>"` and `Search Web for "<selection>"` above Copy when text is selected. Search uses macOS `x-web-search://?...`, avoiding a hardcoded Google search URL.
   - Changed: selection translation now opens a lazy `Translate Selection` panel from the context menu or existing Translate command when text is selected. It has source/target dropdowns, editable input and output text, a Translate button, and remembered language choices. Opening the panel immediately translates the selected text; clicking Translate later replaces any edited output with a fresh local translation of the current input.
   - Changed: selection translation runs Argos on a background queue and reuses the existing installer/package prompts only after the user invokes translation, so launch and render paths do not initialize translation tooling.
   - Validation target: select text, right-click, verify Search Web opens browser search; verify Translate opens the panel, immediately translates with last languages, allows editing input/output, persists changed language dropdowns, and retranslation replaces output without blocking app launch.

48. Post-zoom crisp render guarantee.
   - Status: Implemented for validation; not committed.
   - Prompt link: after some zoom/unzoom cycles, the page can stay blurry forever; when it does render at high zoom, unzoom becomes laggy.
   - Agent finding: the delayed post-live-zoom crop render was gated on `_viewportMovementGeneration`, so ordinary viewport settling could cancel the only crisp fallback without scheduling another one. The same callback rendered MuPDF page crops synchronously on the main thread, which explains the high-zoom unzoom hitch.
   - Changed: the post-live-zoom render no longer treats viewport movement as a cancellation reason. It still validates live-zoom sequence, render generation, path, document presence, and current zoom before applying results.
   - Changed: post-live-zoom viewport crops now render on the page render queue with user-initiated priority and apply back on the main thread only if they still match the current document and zoom. If a document pan is active when the callback fires, it reschedules instead of dropping the crisp pass.
   - Changed: document drawing now prefers the minimap fallback over stale full-page images during zoom transitions and draws viewport crop images only when their zoom matches the current zoom, preventing old high-zoom crops from being scaled during unzoom.
   - Validation target: repeatedly zoom in/out quickly around high zoom on Bear Sunny and long landscape documents; the viewport should never remain permanently blurry, and unzoom should not hitch when the crisp crop arrives.

49. Copy-selected-text newline normalization.
   - Status: Implemented for validation; not committed.
   - Prompt link: do the same replace-newline-with-space text trick when copying selected text, and make it toggleable in the Edit menu with the default on.
   - Changed: document text copy now uses the same whitespace-collapsing helper as selection translation/search when `Replace Line Breaks When Copying Text` is enabled. This affects only `copySelection:`; normal macOS text-field copy remains untouched.
   - Changed: the toggle is checkable in the Edit menu, defaults on for fresh settings, and persists in `settings.json` as `collapseWhitespaceWhenCopyingText`.
   - Validation target: select multiline PDF text and copy; with the Edit-menu toggle on, pasted text should be one whitespace-normalized line. Turn it off and copy again; pasted text should preserve the original selected line breaks.

50. Find-field horizontal navigation and zoom render de-regression.
   - Status: Implemented for validation; not committed.
   - Prompt link: long Find-field text still cannot be navigated horizontally; zoom/unzoom can still leave pages blurry forever and create massive lag when unzooming.
   - Changed: the toolbar Find search field is explicitly single-line, scrollable, non-wrapping, and handles horizontal trackpad scrolling locally by moving/scrolling the field editor through the query instead of letting the event fall through to document scrolling.
   - Changed: live zoom now clears queued render work immediately instead of suspending and carrying stale background work. Queued full-page renders also check the live-zoom sequence before starting expensive work.
   - Changed: post-zoom visible viewport crops are scheduled before full-page/nearby background renders, and those background renders are delayed briefly so the crisp visible crop is not stuck behind stale high-zoom work.
   - Changed: drawing again uses the previous full-page image as the live fallback instead of dropping straight to the minimap image, while stale viewport crops are still ignored when their zoom/scale no longer matches.
   - Validation target: enter a long Find query and verify horizontal trackpad movement/arrows can navigate it. Repeatedly zoom in/out at high zoom; the visible page should crisp up without getting stuck behind background renders, and fast unzoom should not hitch behind stale high-zoom work.

51. High-zoom unzoom lag fallback.
   - Status: Implemented for validation; not committed.
   - Prompt link: when zoomed in, unzoom still has extreme lag.
   - Finding: the live unzoom path could still draw a stale high-resolution full-page bitmap as the fallback after the zoom value changed. Scaling that large image every live-zoom frame can dominate the UI thread.
   - Changed: `SPDFDocumentView` now knows when live zoom is active. During live zoom it draws exact full-page images normally, but if the full-page image is stale it uses the lightweight minimap fallback instead of scaling the stale high-resolution page image. Once zoom settles, the async crisp viewport crop/background render path resumes as before.
   - Validation target: zoom deeply into a page and immediately unzoom; the gesture should stay responsive instead of hitching on stale high-zoom bitmap scaling.

## Validation

- Launch state/persistence lane: cached the Mac support-directory lookup, skipped byte-identical JSON atomic writes, skipped unchanged Mac current-window session writes under the same lock/read flow, and deferred GTK favorites loading behind `ensure_favorites_loaded`. Rendering resolution/timing, tab order, scroll restoration, minimap behavior, and session restore semantics were left untouched.
- Formatting: ran clang-format on touched C/C++/Linux files. Mac ObjC files required an explicit ObjC style because the repo `.clang-format` only declares `Language: Cpp`.
- Diff hygiene: `git diff --check` passed.
- Mac syntax: `clang++ -std=c++17 -fobjc-arc -Icore -I../mupdf/include -fsyntax-only mac/*.mm` passed.
- Mac build: `make -C portable mac-app` passed after fixing the MuPDF PKCS7 target and adding a local `.icns` fallback when `actool` is missing.
- Mac install/smoke: installed to `/Applications/ShenzhenPDF.app`, codesign verification passed, and launched the app with `/Users/raph/Downloads/Bear Sunny Technologies Inc for Blackstar.pdf`.
- Mac long-document minimap regression: temporary Objective-C++ harness against `SPDFMinimapView` verified a 35-page horizontal viewport drag uses the long-document viewport callback, changes `documentCenterX` from `885.11` to `991.49`, avoids the normal center-drag callback, and sends one finish callback.
- Mac long-document minimap overlay regression: temporary Objective-C++ harness against `SPDFMinimapView` verified the displayed overlay matches page-intersection geometry (`y=6.00`, `h=95.61`) instead of the synthetic drag thumb.
- Mac non-continuous page geometry regression: temporary Objective-C++ harness against `SPDFDocumentView` verified page 1 and page 2 center in an 800 pt viewport, tall pages keep a top margin, and continuous page stacking remains unchanged.
- Mac non-continuous minimap overlay regression: temporary Objective-C++ harness against `SPDFMinimapView` verified synthetic single-page minimap geometry highlights only the current page and scales a partial visible page slice to the expected overlay height.
- Mac installed long-document smoke: launched `/Applications/ShenzhenPDF.app` with the 117-page `/Users/raph/Downloads/HRO catalogue韩荣新目录.pdf`, verified the ShenzhenPDF process started, then quit cleanly.
- Mac installed non-continuous regression smoke: installed `/Applications/ShenzhenPDF.app`, launched `/Users/raph/Downloads/Bear Sunny Technologies Inc for Blackstar.pdf`, verified the ShenzhenPDF process started, then quit cleanly.
- Mac installed Mothership non-continuous regression smoke: rebuilt and installed `/Applications/ShenzhenPDF.app`, launched `/Users/raph/Library/CloudStorage/GoogleDrive-raph@blackstar.inc/Shared drives/Blackstar SZ/Mothership/Hardware version 1 - h1/Electronics/Electronics version 1 - e1/ICD Doc/26.6.1.1 - mothership block diagram.drawio.pdf`, verified the ShenzhenPDF process started, and captured `/tmp/shenzhenpdf-single-page-fix.png`.
- Mac tab-loading regression smoke: rebuilt and installed `/Applications/ShenzhenPDF.app`, launched Bear Sunny plus BladeMaster, inspected `~/Library/Application Support/ShenzhenPDF/session.json` for multiple tabs, and verified only `/Applications/ShenzhenPDF.app` exists.
- Mac Finder document icon preview correction: rebuilt and installed `/Applications/ShenzhenPDF.app`, verified the installed `Info.plist` no longer has `CFBundleTypeIconFile` for document types, re-registered LaunchServices, reset Quick Look cache, and restarted Finder.
- Mac green-button fullscreen window movement fallback: rebuilt and installed `/Applications/ShenzhenPDF.app`, verified an app-owned Left Half command exits native fullscreen and applies a half-width frame, and the user confirmed the fullscreen shortcut path works.
- Mac PDF vector printing smoke: built and installed `/Applications/ShenzhenPDF.app`, verified the installed binary links PDFKit, and ran a PDFKit print-to-PDF smoke on Bear Sunny that produced 35 pages with font/text operators (`fonts=146`, `text_ops=3721`) rather than a purely raster page image.
- Mac app uniqueness: after install and smoke, `find` and Spotlight metadata both report only `/Applications/ShenzhenPDF.app` for the ShenzhenPDF bundle id/name.
- Mac launch-performance/hover round: rebuilt and installed `/Applications/ShenzhenPDF.app`, verified codesign, checked `ShenzhenPDF --version`, launched the installed app with `/Users/raph/Downloads/Bear Sunny Technologies Inc for Blackstar.pdf`, verified the process started, then quit cleanly.
- Mac static-launch/page-geometry round: rebuilt and installed `/Applications/ShenzhenPDF.app`, verified codesign, cleaned app JSON state with a timestamped backup, opened `/Users/raph/Downloads/HRO catalogue韩荣新目录.pdf`, confirmed `documents.json` stored exact geometry for 117 pages (`pageGeometryLength=234`), relaunched from that saved state to exercise the seeded geometry cache and pre-visible sidebar metadata path, verified the process started, then quit cleanly.
- Mac zoom/page-turn tweak: ran `git diff --check`, Mac Objective-C++ syntax check, rebuilt and installed `/Applications/ShenzhenPDF.app`, verified CLI version/codesign, launched `/Users/raph/Downloads/Bear Sunny Technologies Inc for Blackstar.pdf`, verified the process started, then quit cleanly. Manual trackpad validation is still needed for the exact continuous zoom drift and single-page drag threshold feel.
- Mac session JSON cleanup: moved current state files to `~/Library/Application Support/ShenzhenPDF/backup-20260603-110422-finder-final` before the latest Finder-style session tests.
- Mac additive Finder-open correction: moved current state files to `~/Library/Application Support/ShenzhenPDF/backup-20260603-122509-additive-final`, verified cold Finder-open restores Bear plus adds/selects the clicked PDF, corrupt clicked PDF preserves Bear only, already-running Finder-open adds/selects, and the installed `/Applications/ShenzhenPDF.app` passes the Bear-plus-clicked-PDF case.
- Linux syntax: `cc -Icore -I../mupdf/include $(pkg-config --cflags gtk+-3.0) -fsyntax-only linux/ShenzhenPDFGtkDisplay.c linux/ShenzhenPDFGtk.c` passed.
- Linux build: `make -C portable linux` passed.
- Linux launch-performance round: `portable/build/ShenzhenPDF-gtk --version` returned `Shenzhen PDF portable gtk 0.5` after the deferred-sidebar metadata change.
- Windows build: `bun ./cmd/build.ts` failed on this macOS machine because Visual Studio 2026 `msbuild.exe` is not available in PATH.
- TestFlight readiness: `portable/check-testflight-ready.sh` reports build tools and OpenSSL OK, but Apple signing/provisioning/Transporter are missing.
