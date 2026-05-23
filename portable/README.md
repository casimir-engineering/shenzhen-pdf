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

Free open-source distribution without an Apple Developer account is best done by
building on the user's Mac instead of asking them to open a downloaded `.app`.
That avoids the browser quarantine path that causes the "Put in Trash" dialog.

From a checkout:

```sh
./portable/install-mac-from-source.sh
```

From a published repository, replace the URL/ref with your fork:

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR-USER/YOUR-REPO/YOUR-BRANCH/portable/install-mac-from-source.sh \
  | bash -s -- https://github.com/YOUR-USER/YOUR-REPO YOUR-BRANCH
```

Development builds are ad-hoc signed so they can run locally. Public macOS
downloads must be signed with an Apple Developer ID certificate and notarized,
otherwise Gatekeeper shows "Apple could not verify..." malware warnings after a
user downloads the app or DMG.

Create a notarization profile once:

```sh
xcrun notarytool store-credentials sumatrapdf-notary \
  --apple-id you@example.com \
  --team-id TEAMID1234 \
  --password app-specific-password
```

Then build the public DMG:

```sh
make -C portable release-dmg \
  MAC_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)" \
  NOTARY_PROFILE=sumatrapdf-notary
```

TestFlight builds are packaged separately for App Store Connect. The publisher
must provide the App Store Bundle ID, Apple Distribution identity, installer
identity, and provisioning profile:

```sh
MAC_BUNDLE_ID=com.example.sumatrapdf \
MAC_BUILD=6 \
MAC_APPSTORE_IDENTITY="Apple Distribution: Friend Name (TEAMID1234)" \
MAC_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Friend Name (TEAMID1234)" \
MAC_PROVISIONING_PROFILE="$HOME/Downloads/SumatraPDF_AppStore.provisionprofile" \
./portable/build-mac-testflight.sh
```

See `portable/docs/testflight.md` for the full App Store Connect handoff.

Build artifacts:

```text
dist/SumatraPDF.app
dist/SumatraPDF-mac-arm64.dmg
dist/SumatraPDF-testflight-0.5.0-6.pkg
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
- Linux shares the portable core and key tabs/search/favorites/sidebar/OCR
  behavior, but the minimap, text-selection overlay, printing, and document
  properties still need GTK-specific UI work.
- OCR modifies the source PDF only after creating a backup named like
  `document_backup.pdf`.
- The default macOS build is ad-hoc signed for local development. Use
  `make -C portable release-dmg` with `MAC_SIGN_IDENTITY` and `NOTARY_PROFILE`
  for distributable signed/notarized builds.
- Use `./portable/build-mac-testflight.sh` for App Store Connect/TestFlight
  packages signed by the publishing Apple Developer account.
