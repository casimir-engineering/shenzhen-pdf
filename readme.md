[![Build](https://github.com/sumatrapdfreader/sumatrapdf/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/sumatrapdfreader/sumatrapdf/actions/workflows/build.yml)

# SumatraPDF

SumatraPDF is a fast, lightweight document reader. The upstream application is a
Windows reader for PDF, EPUB, MOBI, CBZ, CBR, FB2, CHM, XPS, and DjVu files under
the (A)GPLv3 license, with some code under BSD-style licenses. See `AUTHORS` for
details.

This branch also contains an experimental native macOS/Linux port in
[`portable/`](portable/). The port is not Win32 emulation: it keeps MuPDF-backed
document operations in a shared C core and presents them through native AppKit
and GTK frontends.

## Portable Port Preview

![macOS SumatraPDF main window with titlebar tabs, toolbar, continuous PDF view, and minimap](docs/images/portable/macos-main-window.png)

![macOS SumatraPDF search highlights with match count and minimap result markers](docs/images/portable/macos-search-highlights.png)

## What Changed In This Branch

### Shared Portable Core

- Added a platform-neutral MuPDF wrapper in `portable/core`.
- Supports opening documents, page count/title/page size, RGBA rendering, search
  hit rectangles, text selection extraction, outlines, comments/markup
  annotations, and text-presence detection for OCR decisions.
- Keeps Windows headers and Win32 types out of the portable reader layer.

### macOS AppKit Frontend

- Builds a native `.app` and `.dmg`, with an install target for
  `/Applications/SumatraPDF.app`.
- Adds slim titlebar tabs, tab close buttons, a `+` open button, centered tab
  titles with middle ellipsis, tab hover previews, drag/drop open, and session
  restore for previously opened tabs.
- Renders the current document first, then fills pages around the current page
  using background workers so large documents feel responsive.
- Supports single-page and continuous viewing, fit width/height/page, actual
  size, custom zoom memory, smooth zooming, scroll-wheel page changes, and
  right/middle-button panning.
- Adds a Sumatra-style find bar with `Cmd+F`, match count, next/previous arrows,
  yellow highlights, active-match red flash, and per-tab search memory.
- Adds a command palette with `Cmd+K` for favorites first and open-document
  search below, keyboard navigation, direct jumps, and named favorites.
- Supports page and document favorites with `Cmd+B` and `Cmd+Shift+B`, stored in
  readable JSON, including two-step favorite deletion from the palette.
- Adds chapters and comments side panels, comment detection from PDF markup
  annotations, comment hover popovers, and click-to-jump behavior.
- Adds a Sublime-style minimap with page separations, current viewport,
  proportional scrolling, mouse dragging at the current zoom level, search
  markers, and remembered width/visibility.
- Adds text selection/copy, copy current page image, print, properties, show in
  Finder, and open in Acrobat Reader.
- Adds OCR via OCRmyPDF/Tesseract, including an installer flow, progress log,
  multi-core execution, source-PDF backup, and automatic reload after OCR.

### Linux GTK Frontend

- Builds a native GTK binary from the same portable core.
- Opens documents from file picker, command line, and drag/drop.
- Keeps readable JSON settings, session, and favorites in
  `~/.config/sumatrapdf/`.
- Supports chapters/comments side panel, a View menu for showing chapters or
  comments, and remembered side-panel width.
- Supports current-document search with match count, previous/next controls,
  yellow highlights, active-match red border, and restored search state.
- Adds a `Ctrl+K` command dialog for favorites and current-document search,
  keyboard selection with arrows/Enter/Escape, and search-result handoff into
  the document find bar.
- Adds favorites with `Ctrl+B` and `Ctrl+Shift+B`, show in folder, open in
  default browser, scroll/pan navigation, and OCR install/run support using
  OCRmyPDF/Tesseract.
- Uses a GTK render thread pool and renders around the current page first in
  continuous mode.

## Build

### Windows

The original Windows build remains unchanged:

```sh
bun ./cmd/build.ts
```

This creates:

```text
out/dbg64/SumatraPDF.exe
```

### macOS

Build and install the native app:

```sh
make -C portable install
```

Build only the app or DMG:

```sh
make -C portable mac-app
make -C portable dmg
```

Outputs:

```text
dist/SumatraPDF.app
dist/SumatraPDF-mac-arm64.dmg
/Applications/SumatraPDF.app
```

macOS state, session, and favorites are stored as readable JSON in:

```text
~/Library/Application Support/SumatraPDF/
```

### Linux

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

Linux state, session, and favorites are stored as readable JSON in:

```text
~/.config/sumatrapdf/
```

## Current Status

The portable port is experimental. The macOS frontend is currently the most
feature-complete native port. The GTK frontend shares the same core and has
matching search/favorites/sidebar/OCR foundations, but it is still single
document and does not yet expose every macOS UI feature such as titlebar tabs,
the minimap, text-selection overlay, printing, or document properties.

OCR support uses external tools and writes the OCR result back to the source PDF
after creating a backup named like `document_backup.pdf`.

The macOS app is ad-hoc signed for local installation; it is not notarized.

## Repository Layout

- `src/`: original Windows SumatraPDF source.
- `portable/core/`: shared MuPDF-backed portable C API.
- `portable/mac/`: native AppKit frontend.
- `portable/linux/`: native GTK frontend.
- `portable/docs/porting-incompatibilities.md`: Win32 dependency breakdown and
  replacement plan.
- `docs/md/`: existing SumatraPDF documentation.

## Links

- [Website](https://www.sumatrapdfreader.org/free-pdf-reader)
- [Manual](https://www.sumatrapdfreader.org/manual)
- [Developer information](https://www.sumatrapdfreader.org/docs/Contribute-to-SumatraPDF)
- [Portable port notes](portable/README.md)
