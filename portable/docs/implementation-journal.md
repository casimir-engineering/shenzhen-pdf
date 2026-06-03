# Implementation Journal

Date: 2026-06-02

Scope: prompt-linked implementation journal for the current working tree. This records what was changed, what was tested, and what is still not complete.

## Original Prompt Tracker

1. Refactor the 10k-line `.mm` file and keep an eagle view of oversized files.
   - Status: Partially complete, not done.
   - Changed: extracted Mac models, tab strip, document view, minimap, print view, and shortcut-help delegate behavior into dedicated files under `portable/mac/`.
   - Current line counts: `portable/mac/ShenzhenPDFMac.mm` is 7,992 lines; extracted files are 103-749 lines, plus `SPDFMacDelegatePrivate.h` at 337 lines and `ShenzhenMacDelegate+ShortcutHelp.mm` at 234 lines. `portable/linux/ShenzhenPDFGtk.c` is 8,934 lines after one helper extraction.
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

7. Opening a PDF from Finder while the app is in another workspace should switch to the app.
   - Status: Implemented in Mac source; manual Spaces QA still needed.
   - Changed: external open handlers activate/order the target window after opening files.

8. Relaunching should restore split windows promptly in one workspace.
   - Status: Partially treated, not solved.
   - Changed: closing a window removes only that window’s session and suppresses stale rewrite-on-terminate.
   - Changed: direct launch restores stored tabs, but launching with an explicit PDF now skips or discards the restored session so stale documents do not merge into the file-open request. Empty windows and tabs without paths are pruned from `session.json`.
   - Changed: replacement launches validate the clicked PDFs before clearing stored windows, so a corrupt external PDF cannot erase a good previous session.
   - Changed: closing the last app window now saves its tabs before quitting; only non-last windows remove themselves from the stored session.
   - Tested: backed up and cleaned `~/Library/Application Support/ShenzhenPDF/*.json`, then verified clean direct launch, restore-after-quit, cold Finder-style PDF launch replacing the prior session, empty first-window pruning, corrupt external-open preservation, already-running Finder-open adding to the visible restored session, and red-window-close preserving the last window's documents.
   - Gap: session restore still spawns restored windows as separate processes with `--restore-window`. A full fix should migrate to one-process multi-window controllers.

9. Support default Mac move/resize window shortcuts.
   - Status: Implemented in Mac source; manual menu shortcut QA still needed.
   - Changed: added a Window menu with Minimize, Zoom, Fill, Center, Move & Resize halves, and Bring All to Front.
   - Changed: mirrored Fill, Center, and half-window actions under View > Move & Resize Window so they are visible from the menu the user checked.

10. Improve Mac print quality to high DPI.
   - Status: Implemented in Mac source; print-to-PDF visual QA still needed.
   - Changed: printing now uses `SPDFPrintView` to render pages directly from `spdf_document` at a 1200 DPI target with fallback to lower render zoom and then cached pages.

11. Install and prepare for TestFlight.
   - Status: Local user install completed; TestFlight signing is blocked by missing Apple assets.
   - Installed: `/Users/raph/Applications/ShenzhenPDF.app`.
   - Gap: replacing `/Applications/ShenzhenPDF.app` failed because the existing app is root-owned and passwordless sudo is unavailable. TestFlight readiness fails for missing Apple Distribution certificate, 3rd Party Mac Developer Installer certificate, provisioning profile, and Transporter.

## Validation

- Formatting: ran clang-format on touched C/C++/Linux files. Mac ObjC files required an explicit ObjC style because the repo `.clang-format` only declares `Language: Cpp`.
- Diff hygiene: `git diff --check` passed.
- Mac syntax: `clang++ -std=c++17 -fobjc-arc -Icore -I../mupdf/include -fsyntax-only mac/*.mm` passed.
- Mac build: `make -C portable mac-app` passed after fixing the MuPDF PKCS7 target and adding a local `.icns` fallback when `actool` is missing.
- Mac install/smoke: installed to `~/Applications`, codesign verification passed, and launched the app with `/Users/raph/Downloads/Bear Sunny Technologies Inc for Blackstar.pdf`.
- Mac session JSON cleanup: moved current state files to `~/Library/Application Support/ShenzhenPDF/backup-20260603-110422-finder-final` before the latest Finder-style session tests.
- Linux syntax: `cc -Icore -I../mupdf/include $(pkg-config --cflags gtk+-3.0) -fsyntax-only linux/ShenzhenPDFGtkDisplay.c linux/ShenzhenPDFGtk.c` passed.
- Linux build: `make -C portable linux` passed.
- Windows build: `bun ./cmd/build.ts` failed on this macOS machine because Visual Studio 2026 `msbuild.exe` is not available in PATH.
- TestFlight readiness: `portable/check-testflight-ready.sh` reports build tools and OpenSSL OK, but Apple signing/provisioning/Transporter are missing.
