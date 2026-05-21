# SumatraPDF Mac/Linux Porting Incompatibilities

This port avoids Win32 emulation. The existing SumatraPDF document behavior is recovered by isolating the reusable reader concepts behind a portable core, then binding that core to native frontends.

## Decomposition

| Windows dependency | Where it shows up | Replacement path |
| --- | --- | --- |
| `WinMain`, window class registration, COM/common-control startup | `src/SumatraStartup.cpp`, global app setup | Native app bootstrap per platform: AppKit `NSApplication` on macOS, `GtkApplication` on Linux. |
| `HWND`, `HMENU`, `HDC`, `HBITMAP`, `HFONT`, GDI/GDI+ painting | `src/SumatraPDF.cpp`, `src/*Win*.cpp`, `src/utils/wingui/*` | Portable document/render core returns RGBA pixel buffers; frontends draw with AppKit/GTK image widgets and native controls. |
| Win32 message loop and `WM_*` input | Main window/canvas/sidebar handlers | Native event callbacks: Objective-C target/actions and GTK signals. |
| Native Windows toolbar/rebar/status/sidebar widgets | Toolbar, tabs, favorites, book view | AppKit and GTK layouts with equivalent controls: Open, prev/next, page entry, zoom, fit width, search, pages/sidebar. |
| Windows file dialogs and shell integration | Open/recent/open-with handlers | `NSOpenPanel` and Finder document types on macOS; `GtkFileChooserDialog` on Linux. |
| Windows text/search UI and accelerators | Find bar, menu accelerators | Shared `spdf_search_page*` API backed by MuPDF text search; platform menu shortcuts call native actions. |
| Win32 bitmap rendering contract | `RenderedBitmap`, render cache, canvas paint | `spdf_bitmap` RGBA buffer. The UI layer owns presentation, scrolling, and zoom policy. |
| Windows synchronization/threading primitives | Cache/render scheduling | Native frontends now render the active page first and queue surrounding pages on platform worker queues. A reusable render cache is still needed. |
| `IStream`, Windows path and shell helpers | File loading and utility layer | UTF-8 file paths in the portable core; platform frontends translate native file URLs/paths into UTF-8. |
| Windows-only secondary features: DDE, UI Automation, DWM dark mode, CHM/OLE/WebView2, Windows printing | Ancillary integrations | Keep out of the portable core. Re-add only behind platform interfaces when native equivalents exist. |

## Current Portable Slice

- `portable/core` wraps MuPDF for open/count/title/page-size/render/search/outline with no Windows headers.
- `portable/mac` is a native AppKit app bundle target.
- `portable/linux` is a GTK frontend source over the same core.
- `portable/Makefile` builds the macOS `.app`, `.dmg`, installer copy, and a Linux GTK binary target.
- Both native frontends prioritize the current page first and use background workers to fill surrounding pages.

## Next Compatibility Layers

- Add a portable render cache so large PDFs can reuse rendered pages across zoom/view changes.
- Add platform adapters for settings, recent files, keyboard maps, printing, and annotations.
- Gradually move reusable logic from `DisplayModel`, command routing, tab history, and favorites into portable C++ modules once their Win32 handle types are replaced by neutral structs.
