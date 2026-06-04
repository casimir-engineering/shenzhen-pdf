# Portable Shenzhen PDF

This directory contains the native macOS and Linux frontends plus the shared
portable core used by Shenzhen PDF. It does not emulate Win32. Document work
lives in a MuPDF-backed C core, and each platform presents it with native UI.

## Layout

- `core/`: platform-neutral API for opening documents, rendering pages,
  searching, extracting selected text, loading outlines/comments, rotating
  pages, detecting text before OCR, and saving edited PDFs.
- `mac/`: native AppKit application bundle frontend.
- `linux/`: native GTK frontend using the same core API.
- `docs/`: TestFlight and portability notes.

## macOS

Build and install:

```sh
make -C portable install
```

Build artifacts:

```text
dist/ShenzhenPDF.app
dist/ShenzhenPDF-mac-arm64.dmg
dist/ShenzhenPDF-testflight-26.6.4-1.pkg
/Applications/ShenzhenPDF.app
```

Readable state files:

```text
~/Library/Application Support/ShenzhenPDF/settings.json
~/Library/Application Support/ShenzhenPDF/session.json
~/Library/Application Support/ShenzhenPDF/favorites.json
```

TestFlight packages are signed separately for App Store Connect:

```sh
MAC_BUNDLE_ID=com.intuition.shenzhenpdf \
MAC_VERSION=26.6.4 \
MAC_BUILD=1 \
MAC_APPSTORE_IDENTITY="Apple Distribution: Friend Name (TEAMID1234)" \
MAC_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Friend Name (TEAMID1234)" \
MAC_PROVISIONING_PROFILE="$HOME/Downloads/ShenzhenPDF_AppStore.provisionprofile" \
./portable/build-mac-testflight.sh
```

## Linux

Ubuntu/Debian:

```sh
sudo apt install build-essential pkg-config libgtk-3-dev libssl-dev
make -C portable linux
./portable/build/ShenzhenPDF-gtk
```

Fedora:

```sh
sudo dnf install gcc make pkgconf-pkg-config gtk3-devel openssl-devel
make -C portable linux
./portable/build/ShenzhenPDF-gtk
```

Readable state files:

```text
~/.config/shenzhenpdf/settings.json
~/.config/shenzhenpdf/session.json
~/.config/shenzhenpdf/favorites.json
```

## Feature Notes

- Current-page-first rendering with background workers filling surrounding pages.
- Slim tabs, restored sessions, drag/drop open, recent documents, and command
  palette support.
- Continuous and single-page modes, fit width/height/page, actual size, custom
  zoom memory, smooth zooming, panning, and scroll-wheel page navigation.
- `Cmd+F`/`Ctrl+F` find with match counters, result highlights, and regex mode.
- `Cmd+K`/`Ctrl+K` command palette for favorites and open-document search.
- Chapters and comments side panels with filtering and jump behavior.
- Right-side minimap with page separations, viewport rectangle, proportional
  dragging, search markers, and remembered visibility/width.
- OCR via OCRmyPDF/Tesseract with installer flow, progress log, language
  selection, backup creation, save-back, and automatic reload.
- Offline translation via Argos Translate with language package installation and
  translated PDFs saved next to the original.

## Distribution

Ad-hoc macOS builds are suitable for local development only. For public direct
downloads, sign with Developer ID and notarize. For TestFlight, use
`portable/build-mac-testflight.sh` with the publisher's Apple certificates and
provisioning profile.
