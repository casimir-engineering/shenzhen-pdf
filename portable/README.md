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
- `linux/`: native GTK frontend using the same core API and YAML state shapes.
- `docs/`: direct-GitHub release, updater, and portability notes.

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
- Human-readable YAML state under the platform application-support/config
  directory: `settings.yaml`, `session.yaml`, `documents.yaml`,
  `favorites.yaml`, and (macOS) `bookmarks.yaml`; recents live inside
  `settings.yaml`. Legacy `.json` files are auto-migrated on launch, with the
  originals kept as `<name>.json.migrated-backup`.

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

## Direct-GitHub Releases

Release metadata and notes are committed before a candidate is built. Prepare
the metadata on a release branch without any publishing side effects:

```sh
./portable/cut-release.sh --version 26.8.27 --build 1 --prepare-only \
  "concise release summary"
```

After reviewing that commit on `master`, explicitly publish the already-
committed metadata. The command builds a clean arm64/macOS 12.0 DMG, signs it
with Developer ID, submits it for notarization, authenticates it before mount,
verifies the app before execution, then tags and publishes:

```sh
./portable/cut-release.sh --publish
```

Publication is resumable. Rerunning `--publish` accepts refs and a GitHub
release only when they resolve to the exact prepared commit, replaces the
named DMG asset when needed, and downloads it again for a SHA-256 comparison.
Any conflicting tag or asset fails closed.

To build the already committed metadata without tagging, pushing, or publishing:

```sh
./portable/build-mac-release.sh
```

Signing configuration is read from the ignored `portable/.release.env`; start
from `.release.env.example`. Team ID `66LJ4BV7Q3`, bundle ID
`com.intuition.shenzhenpdf`, arm64, macOS 12.0, and release optimization flags
are pinned by the release path. Release notes are tracked under
`portable/docs/releases/`.

## Notes For Contributors

- Keep cross-platform reader behavior in `core/` when possible, and keep
  platform-specific UI behavior in the frontend directories.
- Prefer the existing YAML state formats (shared codec in `core/spdf_yaml.c`)
  so macOS and Linux can continue to share document/session/favorites
  semantics.
- Treat macOS-only polish as macOS-only in docs until the GTK frontend has the
  same behavior implemented and validated.
