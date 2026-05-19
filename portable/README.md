# Portable SumatraPDF Slice

This directory is the start of the Mac/Linux port. It keeps MuPDF document handling in a shared C core and uses native frontends for each desktop.

## macOS

```sh
make -C portable dmg install
```

Outputs:

- `dist/SumatraPDF.app`
- `dist/SumatraPDF-mac-arm64.dmg`
- `/Applications/SumatraPDF.app`

State, session, and favorites are saved as readable JSON files in:

```text
~/Library/Application Support/SumatraPDF/
```

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
```

State, session, and favorites are saved as readable JSON files in:

```text
~/.config/sumatrapdf/
```

## Portable Features

- Slim titlebar tabs on macOS, with search and open-new-document controls.
- Session restore for the last opened documents and active page.
- Search with `Cmd+F` on macOS and `Ctrl+F` on Linux.
- Favorites search with `Cmd+K` on macOS and `Ctrl+K` on Linux.
- Favorite current page with `Cmd+B` on macOS and `Ctrl+B` on Linux.
- Favorite current document with `Cmd+Shift+B` on macOS and `Ctrl+Shift+B` on Linux.
- Drag/drop document open in the main window.

## Layout

- `core/`: platform-neutral MuPDF wrapper for open, page count, title, page size, rendering, search, and outline extraction.
- `mac/`: native AppKit app bundle frontend.
- `linux/`: GTK frontend using the same core API.
- `docs/porting-incompatibilities.md`: incompatibility breakdown and replacement plan.
