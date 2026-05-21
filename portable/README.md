# Portable SumatraPDF Port

This directory contains the experimental native macOS/Linux port of SumatraPDF.
It does not emulate Win32. Instead, document work lives in a shared MuPDF-backed
C core and each platform has a native frontend.

## Layout

- `core/`: platform-neutral API for opening documents, rendering pages,
  searching, extracting selected text, loading outlines/comments, and detecting
  whether a PDF already contains text before OCR.
- `mac/`: native AppKit application bundle frontend.
- `linux/`: native GTK frontend using the same core API.
- `docs/porting-incompatibilities.md`: Win32 dependency breakdown and portable
  replacement plan.

## macOS

Build and install:

```sh
make -C portable install
```

Build artifacts:

```text
dist/SumatraPDF.app
dist/SumatraPDF-mac-arm64.dmg
/Applications/SumatraPDF.app
```

Readable state files:

```text
~/Library/Application Support/SumatraPDF/settings.json
~/Library/Application Support/SumatraPDF/session.json
~/Library/Application Support/SumatraPDF/favorites.json
```

Implemented highlights:

- Titlebar tabs with close buttons, `+` open, hover title previews, middle
  ellipsis, drag/drop open, duplicate-tab switching, and session restore.
- Current-page-first rendering with background workers filling surrounding
  pages.
- Single-page and continuous modes, fit width/height/page, actual size, custom
  zoom memory, smooth zooming, panning, and scroll-wheel page navigation.
- `Cmd+F` find bar with match count, previous/next controls, highlights, active
  match flash, and per-tab search memory.
- `Cmd+K` command palette for favorites and open-document search, with keyboard
  navigation and direct result jumps.
- Named page/document favorites with `Cmd+B` and `Cmd+Shift+B`, readable JSON
  storage, and two-step delete confirmation.
- Chapters and comments side panels, PDF markup comment detection, comment hover
  popovers, and comment/sidebar jump behavior.
- Right-side minimap with page separations, viewport rectangle, proportional
  dragging, search markers, and remembered width/visibility.
- Text selection/copy, copy current page image, print, document properties, show
  in Finder, and open in Acrobat Reader.
- OCR via OCRmyPDF/Tesseract with installer flow, progress log, multi-core run,
  backup creation, save-back, and automatic reload.

## Linux

Install GTK 3 and OpenSSL development packages, then build:

```sh
sudo apt install build-essential pkg-config libgtk-3-dev libssl-dev
make -C portable linux
./portable/build/SumatraPDF-gtk
```

Fedora equivalent:

```sh
sudo dnf install gcc make pkgconf-pkg-config gtk3-devel openssl-devel
make -C portable linux
./portable/build/SumatraPDF-gtk
```

Readable state files:

```text
~/.config/sumatrapdf/settings.json
~/.config/sumatrapdf/session.json
~/.config/sumatrapdf/favorites.json
```

Implemented highlights:

- Native GTK window, command-line/file-picker/drag-drop open, and default-browser
  / show-in-folder integration.
- Current-page-first continuous rendering with a GTK thread pool.
- Chapters/comments side panel, View menu panel toggles, and remembered side
  panel width.
- `Ctrl+F` find with restored search text, match count, previous/next controls,
  yellow highlights, and active red match outline.
- `Ctrl+K` command dialog for favorites and current-document search with
  arrows/Enter/Escape navigation.
- `Ctrl+B` and `Ctrl+Shift+B` favorites stored in readable JSON.
- OCR installer/run flow using OCRmyPDF/Tesseract, source backup, multi-core
  execution, save-back, and reload.

## Caveats

- The portable port is still experimental.
- macOS is currently the most feature-complete frontend.
- Linux shares the portable core and key search/favorites/sidebar/OCR behavior,
  but visible tabs, the minimap, text-selection overlay, printing, and document
  properties still need GTK-specific UI work.
- OCR modifies the source PDF only after creating a backup named like
  `document_backup.pdf`.
- The macOS app is ad-hoc signed for local development and installation; it is
  not notarized.
