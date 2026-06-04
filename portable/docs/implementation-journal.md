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
   - Changed: Mac tab/document switches now cancel active document pan inertia so motion from one tab cannot carry into the next tab.
   - Changed: Mac empty tab-strip chrome plus passive toolbar labels/spacer support first-click window drag, while toolbar controls and tabs keep normal click/drag handling.
   - Changed: Mac render queue concurrency now follows the earlier 60% CPU cap, and minimap-drag visible pages promote already-queued background operations instead of waiting behind older low-priority renders.
   - Changed: Linux `attach_document_to_view` always schedules the existing deferred sidebar metadata load instead of synchronously loading outline/comments before tab-switch paint.
   - Gap: next performance round should move Mac and Linux first-page rastering off the launch/tab-switch foreground path and build exact long-document geometry lazily.

## Validation

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
