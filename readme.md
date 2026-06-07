# Shenzhen PDF

Shenzhen PDF is a fast native PDF reader for macOS, Linux, and Windows.

The project follows the same lightweight reader philosophy that made SumatraPDF
pleasant to use: open instantly, keep the interface compact, make search and
navigation quick, and avoid heavy document-management chrome. Shenzhen PDF is a
separate project and is not affiliated with the SumatraPDF project.

## Screenshots

![macOS main window with tabs, toolbar, side panel, document view, and minimap](docs/images/portable/macos-main-window.png)

![Search highlights with match count and minimap markers](docs/images/portable/macos-search-highlights.png)

## Highlights

- Native macOS AppKit frontend with slim tabs, draggable/detachable tabs,
  restored multi-window sessions, side panels, minimap, OCR, local translation,
  comments, favorites, recent files, and presentation mode.
- Native Linux GTK frontend sharing the portable MuPDF-backed core and matching
  the macOS data formats.
- Windows C++/Win32 build kept in-tree so all three desktop platforms can evolve
  together.
- Human-readable JSON for settings, sessions, document state, favorites, and
  recent documents.
- Current-page-first rendering with background preloading around the active page.
- In-document search, regex search, match counters, keyboard navigation,
  minimap result markers, and per-document search memory.
- OCR via OCRmyPDF/Tesseract with language selection, Chinese traineddata
  support, source backups, and progress feedback.
- Offline translation via Argos Translate, with optional language package
  installation and translated PDFs saved next to the original.

## Build

### macOS

Build the app:

```sh
make -C portable mac-app
```

Build and install locally:

```sh
make -C portable install
```

Build a DMG:

```sh
make -C portable dmg
```

Build artifacts:

```text
dist/ShenzhenPDF.app
dist/ShenzhenPDF-mac-arm64.dmg
/Applications/ShenzhenPDF.app
```

Local development builds are ad-hoc signed. Public downloads must be Developer
ID signed and notarized; TestFlight builds use the App Store signing path below.

### Linux

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

### Windows

```sh
bun ./cmd/build.ts
```

The Windows source tree is currently retained from the existing C++/Win32
codebase. Its executable/resource renaming should be completed and verified in a
Windows build environment before publishing Windows binaries under the Shenzhen
PDF name.

## TestFlight Preparation

The publisher needs an active Apple Developer Program account.

Create once in Apple Developer and App Store Connect:

1. An explicit macOS Bundle ID: `com.intuition.shenzhenpdf`.
2. An App Store Connect macOS app record using that Bundle ID.
3. A Mac App Store distribution provisioning profile.
4. An Apple Distribution certificate.
5. A 3rd Party Mac Developer Installer certificate.

Build the upload package:

```sh
MAC_BUNDLE_ID=com.intuition.shenzhenpdf \
MAC_VERSION=26.6.7 \
MAC_BUILD=1 \
MAC_APPSTORE_IDENTITY="Apple Distribution: Publisher Name (TEAMID1234)" \
MAC_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Publisher Name (TEAMID1234)" \
MAC_PROVISIONING_PROFILE="$HOME/Downloads/ShenzhenPDF_AppStore.provisionprofile" \
./portable/build-mac-testflight.sh
```

Expected output:

```text
dist/ShenzhenPDF-testflight-26.6.7-1.pkg
```

Open in Transporter:

```sh
OPEN_TRANSPORTER=1 ./portable/build-mac-testflight.sh
```

See [portable/docs/testflight.md](portable/docs/testflight.md) for the complete
handoff checklist.

## Data Files

macOS:

```text
~/Library/Application Support/ShenzhenPDF/
```

Linux:

```text
~/.config/shenzhenpdf/
```

Typical files:

```text
settings.json
session.json
documents.json
favorites.json
recent.json
```

## Repository Layout

- `portable/core/`: shared portable document/render/search/OCR-facing core.
- `portable/mac/`: native macOS AppKit application.
- `portable/linux/`: native Linux GTK application.
- `src/`: Windows C++/Win32 application code.
- `mupdf/`: MuPDF dependency.
- `ext/`: third-party dependencies.
- `portable/docs/`: release, TestFlight, and portability notes.

## Legal And Attribution

Shenzhen PDF is free/open-source software. This repository currently retains
source and dependencies that carry their own licenses and notices. Preserve the
license files and per-file copyright notices when publishing:

- `COPYING`
- `COPYING.BSD`
- `AUTHORS`
- `mupdf/COPYING`
- third-party notices under `ext/`, `packages/`, and `mupdf/`

See [NOTICE.md](NOTICE.md) for the publication notice. Before claiming that the
repository contains no inherited code, perform a source audit and remove or
rewrite the retained code first.
