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

## Layout

- `core/`: platform-neutral MuPDF wrapper for open, page count, title, page size, rendering, search, and outline extraction.
- `mac/`: native AppKit app bundle frontend.
- `linux/`: GTK frontend using the same core API.
- `docs/porting-incompatibilities.md`: incompatibility breakdown and replacement plan.
