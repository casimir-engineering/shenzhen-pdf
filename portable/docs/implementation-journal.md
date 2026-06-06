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
   - Next: add the exact page-geometry cache from `portable/docs/launch-performance-strategy.md` so the now-static first frame can also appear faster on restored/recent long PDFs without changing layout.

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
- Mac session JSON cleanup: moved current state files to `~/Library/Application Support/ShenzhenPDF/backup-20260603-110422-finder-final` before the latest Finder-style session tests.
- Mac additive Finder-open correction: moved current state files to `~/Library/Application Support/ShenzhenPDF/backup-20260603-122509-additive-final`, verified cold Finder-open restores Bear plus adds/selects the clicked PDF, corrupt clicked PDF preserves Bear only, already-running Finder-open adds/selects, and the installed `/Applications/ShenzhenPDF.app` passes the Bear-plus-clicked-PDF case.
- Linux syntax: `cc -Icore -I../mupdf/include $(pkg-config --cflags gtk+-3.0) -fsyntax-only linux/ShenzhenPDFGtkDisplay.c linux/ShenzhenPDFGtk.c` passed.
- Linux build: `make -C portable linux` passed.
- Linux launch-performance round: `portable/build/ShenzhenPDF-gtk --version` returned `Shenzhen PDF portable gtk 0.5` after the deferred-sidebar metadata change.
- Windows build: `bun ./cmd/build.ts` failed on this macOS machine because Visual Studio 2026 `msbuild.exe` is not available in PATH.
- TestFlight readiness: `portable/check-testflight-ready.sh` reports build tools and OpenSSL OK, but Apple signing/provisioning/Transporter are missing.
