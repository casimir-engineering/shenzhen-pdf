# Portable Shenzhen PDF

`portable/` contains the shared MuPDF-backed core plus the native macOS and
Linux frontends for Shenzhen PDF. The goal is a small, native reader on each
desktop platform: the portable layer owns document work, and each frontend owns
the platform UI instead of emulating the Windows application.

## Layout

- `core/`: platform-neutral APIs for opening documents, rendering pages,
  searching, extracting selected text, loading outlines/comments, rotating
  pages, detecting text before OCR, and saving edited PDFs.
- `mac/`: native AppKit application bundle frontend.
- `linux/`: native GTK frontend using the same core API and JSON state shapes.
- `docs/`: TestFlight handoff, release, and portability notes.

## Frontend Snapshot

The macOS frontend is the most mature portable frontend today. Recent work has
focused on making it feel like a fast daily reader: restored tab/window
sessions, resident per-tab document caches, current-page-first rendering,
background preloading, responsive live zoom/resize behavior, smoother trackpad
panning, detachable tabs, presentation mode, native window arrangement
shortcuts, default-reader setup, and high quality PDF printing through the
macOS print pipeline.

The Linux GTK frontend shares the portable core, data formats, rendering/search
paths, OCR/translation integration points, and much of the reader model. Some of
the latest UI polish is macOS-specific, but the GTK target remains a first-class
portable frontend rather than a compatibility shim.

## Reader Features

- Compact tabbed UI with drag/drop open, recent documents, favorites, restored
  sessions, remembered zoom/scroll/page state, and command palette support.
- Continuous and single-page modes, fit width/height/page, actual size, custom
  zoom memory, smooth zooming, panning, and scroll-wheel page navigation.
- `Cmd+F`/`Ctrl+F` search with match counters, highlights, keyboard navigation,
  regex mode, per-document memory, and minimap result markers.
- macOS Search sidebar that appears while searching, groups contextual result
  snippets by chapter, and keeps selection synced with next/previous navigation.
- Chapters and comments side panels with filtering and jump behavior.
- Right-side document map with page separations, viewport rectangle,
  proportional dragging, search markers, remembered visibility/width, and
  special handling for long documents and single-page PDFs.
- OCR via OCRmyPDF/Tesseract with installer flow, progress log, language
  selection, Chinese traineddata support, backup creation, save-back, and
  automatic reload.
- Offline translation via Argos Translate with language package installation and
  translated PDFs saved next to the original.
- Human-readable state under the platform application-support/config directory:
  `settings.json`, `session.json`, `documents.json`, `favorites.json`, and
  `recent.json`.

## macOS

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

Common artifacts:

```text
dist/ShenzhenPDF.app
dist/ShenzhenPDF-mac-arm64.dmg
/Applications/ShenzhenPDF.app
```

Readable state files live under:

```text
~/Library/Application Support/ShenzhenPDF/
```

Local development builds are ad-hoc signed. Public direct-download releases
should be Developer ID signed and notarized.

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

Readable state files live under:

```text
~/.config/shenzhenpdf/
```

## TestFlight Handoff

TestFlight packages use the App Store signing path and require the publisher's
Apple assets. Create the Bundle ID, App Store Connect app record, distribution
provisioning profile, Apple Distribution certificate, and 3rd Party Mac
Developer Installer certificate before building the upload package.

```sh
MAC_BUNDLE_ID=com.intuition.shenzhenpdf \
MAC_VERSION=26.6.8 \
MAC_BUILD=1 \
MAC_APPSTORE_IDENTITY="Apple Distribution: Publisher Name (TEAMID1234)" \
MAC_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Publisher Name (TEAMID1234)" \
MAC_PROVISIONING_PROFILE="$HOME/Downloads/ShenzhenPDF_AppStore.provisionprofile" \
./portable/build-mac-testflight.sh
```

Expected output:

```text
dist/ShenzhenPDF-testflight-26.6.8-1.pkg
```

Open in Transporter:

```sh
OPEN_TRANSPORTER=1 ./portable/build-mac-testflight.sh
```

The script and checklist are ready for handoff, but this repository cannot
produce an upload-ready package until the publisher supplies the Apple signing
identity, installer identity, provisioning profile, and optionally Transporter.
See [docs/testflight.md](docs/testflight.md) for the complete checklist.

## Notes For Contributors

- Keep cross-platform reader behavior in `core/` when possible, and keep
  platform-specific UI behavior in the frontend directories.
- Prefer the existing JSON state formats so macOS and Linux can continue to
  share document/session/favorites semantics.
- Treat macOS-only polish as macOS-only in docs until the GTK frontend has the
  same behavior implemented and validated.
