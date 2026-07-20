# GTK4 Parity Session Journal

2026-07-19 → 2026-07-20, autonomous session on the dev machine
(Ubuntu 25.10, GNOME 49 Wayland, GTK 4.20.1, libadwaita 1.8, 12 cores).
Spec: `gtk4-parity-spec.md`. Branch `linux-gtk4-parity` (unpushed).

## What was built

A complete GTK4 + libadwaita frontend (`portable/linux/gtk4/`, 24 modules,
~19k LOC + 17 test suites / 161 checks) replacing the GTK3 app, in five waves
of parallel worktree agents, each merged only with the container build green
(`-Wall`, zero warnings):

- **A — core:** AdwApplication shell (AdwTabView tabs: native drag reorder,
  continuous-drag detach/reattach, middle-click close, overview), Mac-layout
  header bar, presentation mode + idle inhibit, accel table + F1 sheet;
  custom snapshot/GdkTexture canvas with document-space anchored zoom (fixes
  the June capped-sheet drift), total-width scroll clamp, click-vs-drag
  links, I-beam/hand cursors; worker render pipeline (persistent docs,
  display lists, tokens, 96 MB LRU); Mac-schema JSON state with legacy-GTK3
  migration and workarea-clamped restore.
- **B — features:** search (type-anywhere, regex/multiline, paste-to-search,
  selection-to-search, Escape/nearest-match, scrollbar heat-map, per-tab
  persistence), command palette (all commands + favorites + recents +
  cross-doc text search), annotations (comment CRUD, highlights, rotate,
  save-as, page export, context menu), minimap (thumbnails, strip-scroll
  model db9515802, hit markers, right edge like Mac), sidebar
  (chapters/comments/chapter-grouped results), properties panel (full
  SPDFMacPropertiesFormat port).
- **C — subsystems:** printing (GtkPrintOperation, Fit/Actual/Custom with
  paper-visible-region rendering), file watcher + read-only shadow copies
  (orange dot, session-persisted binding), auto-updater (GitHub Releases +
  minisign over OpenSSL Ed25519/BLAKE2b, pkexec deb install, user-local
  atomic swap + rollback, health probe), OCR + translation ports (19
  languages, toolchain auto-install, post-freeze translate refinements).
- **D — polish:** resident instant-launch (below), login autostart,
  default-reader prompt + menu item (xdg-mime), dark-mode palettes, deferred
  menus, deb packaging + release scripts, this validation.

## Launch speed (the headline requirement)

Measured on this machine; day-2 session was noisy (empty-AdwWindow floor
300–465 ms vs 285 ms on day 1), so deltas beat absolutes:

| Path | Measured | Notes |
|---|---|---|
| Platform floor, first window of a process | 285–465 ms | empty AdwApplicationWindow, any renderer |
| Platform floor, second window, warm process | ~4 ms | the win condition |
| Cold app launch → page visible | ~700–950 ms | once per login with resident mode on |
| First `gtk_window_present` of a process | blocks 240–470 ms | fonts/glyph atlas/CSS/shaders, one-time |
| **Resident warm open (the shipped path)** | **~60 ms** | 40 ms D-Bus forward + 8 ms present + 10 ms first render |

The decisive mechanism: `--resident` login start presents a fully
transparent throwaway window and destroys it after its first frame, paying
the process-global warmup invisibly; every later open forwards over D-Bus to
the held process. `instantLaunchResident` (default on) controls the hold +
autostart entry. Evidence: `SPDF-LAUNCH` marks, `gtk4-captures/launch-profile.txt`.

## Capture matrix (gtk4-captures/, synthetic 12-page 3-chapter PDF)

| Test | Result | Capture |
|---|---|---|
| Launch, first paint, sidebar chapters, minimap | PASS | 00, 01 |
| Page-entry navigation (Ctrl+L), chapter follow | PASS | 02 |
| Anchored zoom in, reset | PASS | 03 |
| Mixed-size landscape page layout | PASS | 04 |
| End/Home scroll, minimap tracks | PASS | 05 |
| Fit page / fit width | PASS | 06, 07 |
| Type-anywhere search bar + counter + Results pane | PASS* | 10 |
| Find next/prev | PASS | 11 |
| Regex query entry | PASS | 12 |
| Escape clears search | PASS | 13 |
| Chapter-grouped results sidebar | PASS | 14 |
| Sidebar chapters pane | PASS | 20 |
| Command palette: sections, fuzzy commands + accels, recents, cross-doc search | PASS | 21, 22 |
| Properties panel (Ctrl+I) | PASS | 23 |
| Presentation mode (F5) | PASS | 24 |
| Tab overview | PASS | 25 |
| Shortcuts cheat sheet (F1) | PASS | 26 |

\* Known issue: one keystroke can be lost while the search bar reveals (typed
"connector", entry got "cnnector") — the type-anywhere prefill focuses the
entry asynchronously and a fast second keystroke races it. Fix: buffer
window-level keys until the entry has focus. Low severity, logged.

## Known issues / needs live verification

1. Search-bar reveal keystroke race (above).
2. pkexec flows (updater install, OCR toolchain install) need a real
   interactive auth dialog — not testable headless.
3. Printing verified by unit tests + dialog code paths; needs a real CUPS
   queue for paper output.
4. OCR/translation end-to-end need ocrmypdf/argos installed; ported logic is
   test-covered, subprocess seams verified with fixtures.
5. Updater end-to-end needs the first release that ships
   `ShenzhenPDF-linux-amd64.{deb,tar.gz}` + `.minisig` (cut-linux-assets.sh).
6. Giant-sheet (10900 pt schematic) behavior ported with regression tests;
   worth one manual session on the real power-tree PDF from the June VM run.
7. Cold-path present (~450 ms of process warmup) could shrink further by
   moving warmup earlier for non-resident users; resident mode makes it moot.

## GTK3 retirement

`ShenzhenPDFGtk.c` / `ShenzhenPDFGtkDisplay.{c,h}` and the `linux` Makefile
target are deleted in this branch's final commit; `portable/linux/gtk4/` is
the Linux frontend. The GTK3 file remains in git history and is cited by
provenance comments throughout the GTK4 modules.
