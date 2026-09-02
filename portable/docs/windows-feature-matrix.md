# Windows Feature Matrix — every shipped feature vs. `portable/win/` today

Audited 2026-09-02 against **HEAD `5677cc628`** (branch `master`), by building and
running the tree, not from memory. Companion to `windows-native-observations.md`
(§2.1 parity ledger, §7 roadmap) and `windows-port-handoff.md` (§1.4 original
ledger); **where those disagree with this file, this file is newer and was
checked against the tree.** A wrong DONE here costs weeks, so DONE is only given
where a test or a recorded live observation pins the behaviour; code that exists
but was never exercised is PARTIAL with the missing evidence named.

## Scope

Sources read, in order: `portable/docs/releases/*.md` (26.7.17-1 … 26.9.1-2), the
tagged release commit bodies (`26.6.17-1 … 26.9.2-1`) and the untagged
`Release …` commits (26.6.25-1, 26.8.27-1, 26.8.28-1/-2, 26.8.30-1), `readme.md`,
`portable/docs/release-notes-next.md`. **`docs/releasenotes.txt` is SumatraPDF's
changelog (0.1 → 3.6) and is out of scope**: `windows-port-handoff.md` §1.1
establishes that the inherited `src/` tree is a different application with a
different document engine and zero references to `shenzhen_pdf_core`, so none of
its features (DDE, browser plugin, IFilter, CHM, manga mode, …) are ShenzhenPDF
features and none are audited here. Do not re-ask.

Two facts about the checkout that change how to read the sources:

- **Tag `26.9.2-1` is not an ancestor of HEAD.** `origin/master` is 24 commits
  ahead (`ca2273eb0..fab066c88`: flowchart layout, page-sized figures, Markdown
  rotation, faster launch, code copy button, tab outline) and local `master` is 10
  commits ahead of it (the Windows work `1da3611b7..5677cc628`). At HEAD there is
  no `releases/26.9.2-1.md` and the readme says "Latest 26.9.1-2". The 26.9.2-1
  features are recorded below from the tag's notes and marked *(origin only)*.
- **The working tree was not clean during the audit.** `spdf_win_menu.h` carried
  an uncommitted 50-line edit from a parallel track (new command ids, `F5`/`F11`
  rows) that does not compile (`SPDF_WIN_KEY_F5`/`F11` undeclared, one table row
  split). The working-tree run therefore reports `app.build` FAIL and 6 failures;
  **every verdict below is against HEAD**, built in a detached worktree.

## Evidence gathered for this audit (all by exit code)

| Check | Result |
|---|---|
| `run-tests-native.sh` on a clean HEAD worktree (`SPDF_OUT=C:\spdf-build-audit-head`) | **56 cases, 48 passed, 0 failed, 8 blocked, exit 2** — blocked: `SPDFCorePasswordTests` (needs qpdf) and the 7 cross-host PNG cases (need a Mac) |
| `run-tests-native.sh` on the working tree | 56 cases, 42 passed, **6 failed** (`app.build`, `win.menu_test`, 4× `d2d.compose-*`), all from the uncommitted `spdf_win_menu.h` edit |
| `layout-differential-native.cmd` (vs `spdf_docview_internal.h`) | 395,514 comparisons, 0 mismatches |
| `minimap-differential-native.cmd` (vs `spdf_minimap_internal.h`) | 131,503 comparisons, all identical |
| `search-differential-native.cmd` (vs `spdf_search_internal.h`) | 37,440 comparisons, 0 differ |
| `selection-differential-native.cmd` (vs `spdf_selection_adapter.c` + cursor regions) | 50,171 comparisons, 0 differ |
| `props-differential-native.cmd` (vs `spdf_props_internal.h`) | 187,315 comparisons, 0 mismatches |
| `print-differential-native.cmd` (vs `spdf_print.c` pure half) | 1,944,132 comparisons, 0 mismatches |
| `ShenzhenPDF.exe --render-window-png --chrome --dpi 1.5 --find fixture outline.pdf 0 1500 950` light and `--dark` | exit 0 both; strip/toolbar/sidebar rows (incl. `Überblick`, `第一章`)/canvas/heat-map/minimap composed; dark paper sampled `(30,30,30)` = `#1E1E1E` |
| `--render-window-png --fit height` / `--fit page` | exit 0, geometry printed (fit-height is a real mode) |
| A generated `.cbz` (two PNG pages) through `--render-png` and `--render-window-png --dark` | exit 0; in dark the comic page centre stays `(255,255,255)` — picture documents are not recoloured |
| Live-window criteria (open, repaint, DPI, close; client area byte-identical to headless) | **not re-run here** (would steal focus from the user's own instance, pid 8240); taken from `windows-native-observations.md` §0/§4.6 (`verify-phase1.ps1` 7/7 light and dark) and `portable/docs/windows-captures/` |

Verdicts: **DONE** (pinned by a test or a recorded live observation), **PARTIAL**
(both halves cited), **MISSING** (with the macOS/GTK4 original to port from — the
port rule is `windows-port-plan.md` §2.3: toolkit-free logic is transcribed and
differentially tested, never re-derived), **N/A** (settled not-1:1, citation given).
Sizes are LOC of the original to port. "TF" marks a toolkit-free original.

## The matrix

### Reading

| Feature | First shipped | macOS | Linux | Windows | Evidence / where the original lives | Notes |
|---|---|---|---|---|---|---|
| Native window: opens a PDF, renders, repaints on resize, fractional DPI, exits 0 | 26.6.17-1 | ✓ | ✓ | **DONE** | `spdf_win_window.cpp`, `spdf_win_d2d.cpp`; `verify-phase1.ps1` 7/7 light+dark (observations §0, §4.6); `d2d.compose-*` 4/4 PASS this audit; client area byte-identical to headless compose | GPU vs SOFTWARE resampling differs bit-for-bit (observations §4.3); zero-tolerance cases are SOFTWARE↔SOFTWARE |
| Compact tab strip: tabs, close box, `+`, overflow `…`, middle-click close, extension-stripped titles | 26.6.17-1 | ✓ | ✓ | **PARTIAL** | Done: `spdf_win_tabstrip.h` ← `SPDFMacTabStripView.mm`/`SPDFMacTabStripGeometry.h` (`tabstrip_geometry_test` 741 asserts), `chrome_input_test` test_tabstrip_actions, overflow popup `spdf_win_menu_tab_overflow`, middle-click `spdf_win_chrome_input.h:358`, `strip_known_extension` `spdf_win_chrome_model.cpp:38`, live in `windows-captures/01-window-light.png`. Missing: same-name disambiguation (`SPDFMacSupport.mm:82 spdf_disambiguated_display_names_for_paths`, TF), read-only dot never set (`chrome_model.cpp:156`), tab-title hover preview | 26.9.2-1's unselected-tab hairline *(origin only)* also absent. Headless `--chrome` frames have no tab model, so tabs appear only in live captures |
| Drag to reorder, tear off into a new window, continuous drag reattach, yellow drop indicator | 26.6.17-1 / 26.7.17-1 | ✓ | ✓ (AdwTabView) | **PARTIAL** | Reorder DONE: `chrome_drop_tab` in `spdf_win_chrome_tabs_ui.h` via `spdf_win_tabstrip_drop_slot/move_index` (transcribed), `tabs_test` test_insert_and_move. Missing: drop indicator (`spdf_win_chrome_state.h` "NOT DRAWN YET"), detach/reattach — needs multi-window (`SPDFMacTabStripView.mm:519-699`, pasteboard type `:23`; GTK `spdf_window.c:391 tab_view_create_window`) | Detach on Windows = spawn a second process + hand the tab over via `session.yaml` |
| Multi-window session restore (every window, its tabs, selected tab, size) | 26.6.17-1 | ✓ | ✓ | **PARTIAL** | Done: per-window merge under `session.lock`, other windows and unknown keys preserved (`session_test`: test_save_preserves_other_windows_and_unknown_keys, test_concurrent_writers_serialise, test_reads_a_mac_written_session). Missing: New Window command, window geometry never written (`spdf_win_session.cpp:204`), closing the last tab quits (`spdf_win_chrome_tabs_ui.h:39`) where macOS keeps an empty window, session written only at exit | A bare launch restores the first window or opens empty (`488e983bf`) |
| Resume exactly where you left off: page, zoom, fit mode, scroll, search | 26.6.17-1 | ✓ | ✓ | **PARTIAL** | Page restored on first paint (`spdf_win_chrome_scene.h:185`); restore is lazy (`tabs_test` test_nothing_opens_until_it_is_looked_at). Lossy: fit mode collapses to width/custom (`spdf_win_tabs_app.h:59-60`), scroll offset written but never replayed (`spdf_win_chrome_actions.h:200` note), `searchText` carried through untouched, not restored (`spdf_win_session.h` header) | Zoom written but a fit-mode tab re-fits on show |
| Recents, reopen last closed (Ctrl+Shift+T), favorites, Cmd+K palette (commands, "fav" keyword, open-docs-first) | 26.6.17-1 / 26.7.9-1 | ✓ | ✓ | **MISSING** | `documents.yaml`/`favorites.yaml` named in `spdf_win_state.h` but never read or written (grep: 0 users). Port from GTK `spdf_palette.c` (1,267; pure filter half TF, `palette_filter_test.c`), `spdf_state.c` recents/favorites schema (`spdf_state_internal.h` TF), mac `SPDFMacPaletteResults.mm` (145, TF), `ShenzhenPDFMac.mm showPaletteWithTitle` | Ids pre-declared in the in-flight `spdf_win_menu.h` edit, handlers absent |
| Presentation mode (Shift+Cmd+F / F5), Full Screen, prevent sleep | 26.6.17-1 | ✓ | ✓ | **MISSING** | Model flag `presentation` collapses strip+toolbar (`spdf_win_chrome_state.h:96`, `spdf_win_chrome.h:296,388`) but nothing sets it; no borderless/fullscreen window path. Originals: `SPDFMacPresentationIntegration.mm` (64), GTK `win.presentation` in `spdf_window.c`, setting `preventSleepInPresentation` | Small: the chrome already knows how to disappear |
| Dark reading theme for every document (toggle, Shift+Cmd+I, luma remap keeps colour, `#1E1E1E` paper, `#121212` gutter, 1 px `#333` border, follows system, frame follows) | 26.8.30-1 | ✓ | **✗** (0 refs to `SPDF_RENDER_DARK_THEME` in gtk4) | **PARTIAL** | Done: `chrome_toggle_theme` `spdf_win_chrome_actions.h:200`, Ctrl+Shift+I in `menu_test`, system theme `spdf_win_main.cpp:436`, DWM frame `spdf_win_window_frame.h:60`; palette measured in a live window (observations §2); `d2d_theme_test`, `SPDFCoreRenderThemeTests` PASS; paper sampled `#1E1E1E` this audit. Missing: persistence (`"markdownTheme"` key never read/written), toggle rebuilds the canvas and loses the scroll offset | Windows is **ahead of Linux** here (plan §8) |
| Keep Image Colors in Dark Theme (setting, default on; scans still darkened; comics never touched) | 26.8.31-1 / 26.9.1-1 | ✓ | ✗ | **PARTIAL** | Behaviour DONE via core (`spdf_recolor.c`; `SPDFCoreRecolorTests`, `RenderThemeTests` PASS; CBZ dark render stays white this audit) and forced on with dark (`spdf_win_main.cpp --dark`, `chrome_actions.h:205`). Missing: the setting itself and `"darkThemePreservesImages"` persistence | Matches the default by accident, not by design (handoff §3.2) |
| Print / Save as PDF / Copy Page never carry the dark theme | 26.8.31-1 | ✓ | n/a | **DONE** | `spdf_win_export_render_flags()` (`spdf_win_export.h`); `light_theme_test` (flag word, Copy Page Image pixels, printed sheet) PASS | |
| Text selection: drag, double-click word, triple-click block, CJK/OCR layers, drag on a link selects | 26.6.17-1 / 26.8.27-1 / 26.8.29-2 | ✓ | ✓ | **DONE** | `spdf_win_selection.{h,cpp}`, `spdf_win_canvas_selection.cpp` (SM_CXDRAG threshold); `selection_model_test`, `canvas_selection_test`, `selection_differential` 50,171/0 vs `spdf_selection_adapter.c`; core `SPDFCoreSelectionTests`, `SPDFCoreCJKSelectionTests` PASS natively; overlay drawn (`overlay_paint_test`, `f737db23e`) | Select All (Ctrl+A) absent; Escape drops the selection (`key_for_window`) |
| Cursor feedback: I-beam over text, hand over links, grab while panning | 26.7.17-1 | ✓ | ✓ | **PARTIAL** | Cursor regions transcribed from `spdf_docview_internal.h` ← `SPDFMacCursorRegions.mm` (`spdf_win_links.h` §1, differential 0 differ); `canvas_cursor_override` in `spdf_win_chrome_canvas_ui.h`. Missing: hand over **plain-text URLs** on hover (`spdf_win_links.h:27` — needs the worker-thread region build both originals have) | Click on a text URL still follows it |
| Links: annotation + text URLs, internal jump instant and top-aligned to the named destination, external via browser with a second-click cancel | 26.6.17-1 / 26.9.1-1 | ✓ | ✓ | **PARTIAL** | Done: `spdf_win_links.cpp` (`detect_text_links` 0 on hover / 1 on click), `canvas_release` follows on release, http/https/mailto allow-list `spdf_win_chrome_canvas_ui.h:89`, `link_test` PASS. Divergent: internal jump lands at the **top of the page**, ignoring the destination y (`spdf_win_links.h:145-156` states it); no delayed activation for external links (`SPDFMacDelayedLinkActivation.mm`, 35, TF) | |
| Copy selected text (Ctrl+C, CF_UNICODETEXT); copying always allowed | 26.6.17-1 / 26.9.1-1 | ✓ | ✓ (dead gate kept on purpose) | **DONE** | `spdf_win_clipboard_put_utf8`; `clipboard_test` (block composition byte-for-byte; round-trip SKIPs when the workstation is locked); no copy gate by rule (`spdf_win_selection.h` §5) | |
| Zoom: Ctrl+wheel anchored under the cursor, `+`/`-`, 100 %, Fit Width / Height / Page, fit popup | 26.6.17-1 | ✓ | ✓ | **DONE** | `spdf_win_layout.h` ← `spdf_docview_internal.h`, layout differential 395,514/0 this audit; `layout_geometry_test`; Fit Height `099a68508`, `--fit height` exit 0 this audit; accelerators pinned by `menu_test` test_fit_keys_match_the_other_two_frontends | The fit "popup" is a click-to-cycle control, not a menu (`chrome_cycle_fit`, `spdf_win_chrome_actions.h:178`) |
| Continuous canvas: pages centred on one midline, gaps, crop regime for giant sheets, 96 MB cap | 26.6.17-1 | ✓ | ✓ | **DONE** | `spdf_win_canvas.cpp`, `spdf_win_layout.h`; differential above; QC F4 closed | Vertical outer margin is 13 pt (GTK) vs macOS 22 (handoff §3.4) |
| Scrollbars (always visible, thumb drag, trough paging) with the search heat-map | 26.6.17-1 | ✓ | ✓ | **DONE** | `spdf_win_chrome_scroll.h`, `spdf_win_chrome_scrollbar.cpp`; `chrome_scroll_test`, `chrome_scroll_input_test`, `find_overlay_test` test_thin_marks; ticks visible in this audit's composes | |
| Window: 1120×800 default, 560×380 minimum, tab strip inside the title bar, drawn caption buttons, double-click title bar maximises, "`<name> - Shenzhen PDF`" | 26.6.17-1 / 26.8.27-1 | ✓ | ✓ | **DONE** | `initial_client_size` (`spdf_win_main.cpp`), `WM_GETMINMAXINFO` (`spdf_win_window.cpp:301`), `spdf_win_window_caption.h` (`chrome_nc_test` 5,552 hit checks, `chrome_caption_paint_test`), `f06bc4cd0` | Cosmetic leftovers in observations §7.1 |
| Clicking a tab focuses the window; Ctrl+scroll zooms an unfocused window | 26.9.1-2 | ✓ | n/a | **DONE** | `SetFocus` on every `WM_LBUTTONDOWN` (`spdf_win_window.cpp` window_proc) | macOS-specific fix; Windows never had the bug |
| Password-protected PDFs: secure prompt, retry, cancel, no persistence | 26.8.27-1 | ✓ | ✓ | **MISSING** | Core has `spdf_open_with_password`/`spdf_needs_password`; `SPDFCorePasswordTests` BLOCKED natively (install qpdf). No prompt anywhere in `portable/win/src` (only the Properties "password protected" note). Port GTK `spdf_password_lifecycle.c` + `spdf_password_controller.c` (354, TF, `password_lifecycle_test.c`) and `spdf_password_prompt.c` (223) → a Win32 dialog; mac `SPDFMacPassword.mm` (370) | An encrypted PDF currently fails to open with the core's error text |
| Annotations: highlights, text comments, edit/delete, comment author, Comments sidebar, click-to-edit markers, hover preview | 26.6.17-1 | ✓ | ✓ | **MISSING** | Core API exists (`spdf_load_comments`, `spdf_add_highlight_comment`, `spdf_add_text_comment`, `spdf_update_comment`, `spdf_delete_comment`). Windows draws a "No Comments" placeholder (`spdf_win_chrome_sidebar.cpp:226`) and the Chapters/Comments/Search control is not clickable (`spdf_win_chrome_input.h` SIDEBAR case). Port GTK `spdf_annot.c` (1,301), `spdf_sidebar.c` comments half; mac `ShenzhenPDFMac.mm` | Also blocks the Properties "Comments" count (passed as 0) |
| Page rotate clockwise / anticlockwise (Cmd+R) | 26.6.17-1 | ✓ | ✓ | **MISSING** | Core `spdf_rotate_page`; GTK `win.rotate-cw/ccw` (`spdf_annot.c`), mac View menu. Canvas must re-measure the page (`spdf_win_canvas_set_page_size_cache`-style invalidation) | Markdown rotation (26.9.2-1, origin only) is a Markdown-family item |
| Type anywhere to search; select text then Cmd+F seeds the query; Cmd+V searches the clipboard | 26.6.17-1 / 26.7.17-1 | ✓ | ✓ | **MISSING** | `chrome_char` returns 0 with no focused field (`spdf_win_chrome_commands.h:124`); `SPDF_WIN_CMD_FIND` only focuses the field (`:286`); no Ctrl+V route. Originals: `ShenzhenPDFMac.mm:10425 documentTypeToSearchKeyDown`, GTK `spdf_search.c` window-level type-anywhere + paste-to-search | All three are a few lines each once the find field exists — which it does |
| macOS-only File-menu extras: Open Path… (Cmd+Shift+O), Open in Adobe Acrobat Reader, Delete All Text…, Replace Line Breaks When Copying, Set Author for Comments… | 26.6.17-1 | ✓ | Copy Path only | **MISSING** | Core `spdf_delete_all_text` exists; the rest is shell work. Not in the readme's feature list | Low value; listed for completeness |

### Markdown

| Feature | First shipped | macOS | Linux | Windows | Evidence / where the original lives | Notes |
|---|---|---|---|---|---|---|
| Markdown reader family: GFM typography, tables, code boxes + 31-language highlighting + in-place picker, sanitized README HTML, Mermaid/js-sequence/flowchart diagrams with selectable labels, LaTeX math, local + remote images with cache, Obsidian dark palette, A−/A＋ text size, chapters/map/search/selection parity, Save as PDF / Print / Copy Page, translate selection, type-to-search | 26.8.27-1 → 26.8.31-3 (+26.9.2-1 origin only: flowchart layering, page-sized figures, Rotate, code copy button) | ✓ | **✗** (readme tags macOS; 0 refs in gtk4) | **PARTIAL** | Wired 2026-09-02: the core reader (`portable/core/spdf_markdown*.c` over md4c) opens `.md` as pages at every open site through `spdf_win_open_document` -> `spdf_win_md_open_any` (tab model, render workers, search, thumbnails, links, print, headless); A-/A+ on the View menu (Ctrl+Alt+-/=, `markdownFontScale`); Save As / Save Page As / Copy Page through `spdf_export_pdf`; remote images fetched to a cache and re-shown; `md_win_test`, `markdown_open_test`, `SPDFCoreMarkdownTests` pass; captures 03-06. Missing: the toolbar A-/A+ pill (tools track), Translate Selection, diagrams/HTML sanitising parity unaudited. Was: **18,138 LOC**: `portable/mac/markdown/` 11,528 (64 files) + `portable/mac/SPDFMacMarkdown*` 6,610. Dependency stack already portable C: `ext/md4c` (6,462), `ext/gumbo-parser` (33,356). ~5,600 LOC is AppKit-free but Foundation-saturated (plan §3). Text measured in 4 places, drawn in 4 files; DirectWrite is CoreText's peer | Plan §3/§4 Phase 8: "a separate project", 4–8 multi-agent days, out of scope for Phases 1–7. The **coordinator decides** whether it precedes or follows the PDF gaps below |
| Markdown pagination identical to macOS (same page breaks, same line fragments) | — | — | — | **N/A-BY-DESIGN** | `windows-port-plan.md` §3 "(b)", `portable/mac/markdown/README.md:28-45`, handoff §4: TextKit's fragment boundaries define the coordinate space; parity means same content/styling/features, internally consistent coordinates, **not** the same page breaks | Product decision already taken; do not relitigate |

### Search & map

| Feature | First shipped | macOS | Linux | Windows | Evidence / where the original lives | Notes |
|---|---|---|---|---|---|---|
| Incremental find: live "current / total" counter, in-page highlights, active-match ring, regex, invalid pattern fails gracefully | 26.6.17-1 | ✓ | ✓ | **DONE** | `spdf_win_search.h` ← `spdf_search_internal.h` (differential 37,440/0), worker `spdf_win_search.cpp` (own document handle, generation cancel), toolbar controls `spdf_win_chrome_find.{h,cpp}`; `find_overlay_test` (counter's four states, engine, overlays), `chrome_field_input_test`; highlights + heat-map visible in this audit's composes; `--find` drives the real path | Counter not visible in a single-frame headless compose (worker not finished); pinned by test_counter_text. Ring animation not verified |
| Match navigation: Return/Shift+Return, prev/next pill, Ctrl+G, centred scroll-to-match, "search jumps to the nearest result", Escape clears | 26.6.17-1 / 26.7.9-1 | ✓ | ✓ | **PARTIAL** | Stepping DONE (`chrome_find_step`, `menu_test`). Missing: scroll lands on the match's **page**, not the match (`spdf_win_chrome_field_ui.h:52` — canvas has no scroll-to-rect); nearest-match jump never called (`spdf_win_search_nearest_match` ported, 0 uses in `spdf_win_search.cpp`; setting `searchJumpsToNearestResult`); **Escape with nothing focused closes the window** (`spdf_win_window.cpp:354`) — macOS never does | The Escape divergence is a one-line fix and a real usability hazard |
| Regex **multiline** (patterns across line/paragraph breaks) | 26.6.17-1 | ✓ | ✓ | **PARTIAL** | Regex toggle DONE; `regex_multiline` is hard-wired 0 (`spdf_win_search.cpp:255`), no menu item (`ShenzhenPDFMac.mm` "Regex Multiline", GTK `search_regex_multiline`) | Core already takes the flag (`spdf_search_page_rects_options`) |
| Chapter-grouped results sidebar with snippets, Search segment appears while a query is live | 26.6.17-1 | ✓ | ✓ | **MISSING** | Search segment draws "No Results" (`spdf_win_chrome_sidebar.cpp:230`); `SpdfWinSearchMatch` already carries `chapter_index` and snippets. Port `spdf_sidebar_internal.h` (278, 10 inline fns, TF) + GTK `spdf_sidebar.c` (1,246) results half; mac `rebuildSidebar` (`ShenzhenPDFMac.mm:9813-9905`) | Sidebar min width already widens to 216 pt in search mode |
| Document map: live thumbnails, median-scaled strip, draggable viewport, click to jump, Cmd-scroll zoom, scroll-the-strip, one-notch-one-page, search markers, resizable 72–260 pt | 26.6.17-1 / 26.7.17-1 / 26.8.27-1 | ✓ | ✓ | **PARTIAL** | Done: geometry `spdf_win_minimap.h` ← `spdf_minimap_internal.h` (differential 131,503 identical; `minimap_geometry_test`), real thumbnails off-thread (`spdf_win_chrome_thumbs.cpp`, WARM priority, 32 MB LRU), viewport rect drawn (`spdf_win_chrome_minimap.cpp`), width drag via divider (`SPDF_WIN_CA_DRAG_MINIMAP`). Missing: **no pointer action inside the strip** (`spdf_win_chrome_input.h` has no minimap action — clicks/drags/wheel are swallowed), search markers in the strip not drawn (ticks exist only on the scrollbar), width not persisted (`minimapWidth`) | The hardest parts (geometry, hit-testing, thumb window) are already ported and tested; what is left is routing |
| Scrollbar heat-map; each tab remembers its query across switches and relaunches | 26.6.17-1 | ✓ | ✓ | **PARTIAL** | Heat-map DONE (above). Query is one process-wide session (`spdf_win_find_shared`), not per tab, and `searchText` is not restored from the session | |
| Chapters sidebar: outline with nesting, unresolved rows greyed, case+diacritic-insensitive filter, click to jump, current-page selection; EPUB chapters resolve | 26.6.17-1 / 26.8.27-1 | ✓ | ✓ | **DONE** | `spdf_win_chrome_content.{h,cpp}` (`spdf_load_outline` on first paint that needs it), `spdf_win_chrome_sidebar.cpp`; `sidebar_rows_test`, `chrome_field_input_test`; `SPDFCoreOutlineTests` PASS natively (EPUB resolution is core, `shenzhen_pdf_core.c:1474`); UTF-8 titles visible in captures and this audit's compose | Not done: hide the panel when a document has no chapters/comments/search (mac `rebuildSidebar`) — Windows shows "No Chapters"; sidebar width/visibility not persisted |

### OCR & translation

| Feature | First shipped | macOS | Linux | Windows | Evidence / where the original lives | Notes |
|---|---|---|---|---|---|---|
| Local OCR (OCRmyPDF + Tesseract), ~20 languages, one job per core, deskew, backup, one-click toolchain install with live log | 26.6.17-1 | ✓ | ✓ | **MISSING** | Toolbar OCR button is a placeholder glyph with no action (`spdf_win_chrome_toolbar.cpp:297`; `spdf_win_chrome_input.h` toolbar switch has no `TB_OCR` case). Port GTK `spdf_ocr.c` (707) + `spdf_toolchain.c` (725; `ocr_test.c`, `toolchain_test.c`); mac OCR blocks in `ShenzhenPDFMac.mm` | Needs a Windows toolchain-acquisition decision first (no Homebrew/apt: winget? pip? bundled?) |
| Offline translation (Argos): selection and whole document (`<name>_<lang>.pdf`, chapters + comments translated, cancellable) | 26.6.17-1 / 26.7.9-1 | ✓ | ✓ | **MISSING** | Core half portable (`spdf_save_translated_copy_full`, `spdf_translation_should_translate`). Toolbar translate button inert (same as OCR). Port GTK `spdf_translate.c` (1,631; `translate_test.c`), mac `SPDFMacTranslationPolicy.mm`+`Enablement.mm` (71, TF), `SPDFTranslation*Tests.mm` | Same toolchain question (Python + argostranslate on Windows) |

### Speed

| Feature | First shipped | macOS | Linux | Windows | Evidence / where the original lives | Notes |
|---|---|---|---|---|---|---|
| Snappy rendering: visible page first at high priority, neighbours warm up, cached display lists, crop-to-viewport, stale renders abort in ms, instant tab switch (inactive tabs pre-warmed) | 26.6.17-1 | ✓ | ✓ | **PARTIAL** | Done: worker pool with priorities, coalescing, cancellation, callback-exactly-once (`spdf_win_render.c`, `render_service_test`), byte-capped LRU (`lru_cache_test`), neighbour prefetch (`spdf_win_canvas_prefetch.cpp`). Missing: the **visible page renders synchronously on the UI thread** (`spdf_win_canvas.cpp:17` "SYNCHRONOUSLY … even though a worker pool is right there"), one canvas per process so inactive tabs are never warmed (`spdf_win_tabs_app.h` header; mac `SPDFMacInactivePreload.mm` 124, `SPDFMacLaunchWorkPolicy.mm` 323, TF) | 26.9.2-1's launch-prerender retargeting *(origin only)* is macOS-specific |
| MuPDF 1.27.2 statically linked behind the portable core; render byte-identical to macOS | 26.6.17-1 | ✓ | ✓ | **DONE** | 7 of 8 core suites PASS natively (`SPDFCorePasswordTests` needs qpdf); ARM64↔ARM64 byte identity measured (handoff §1.3); `d2d.compose-*` byte-identical | **x64↔ARM64 identity is unmeasured** (observations §1) — the 7 cross-host cases stay BLOCKED without a Mac or committed references |
| Far more than PDF: XPS, CBZ/comics, EPUB/MOBI, images, FB2, HTML | 26.6.17-1 | ✓ | ✓ | **DONE** (core) | This audit: a generated CBZ renders through the Windows exe (`--render-png` exit 0, 675×525) and stays un-recoloured in `--dark`; open-dialog filter lists all formats (`spdf_win_menu.cpp:733`) | No EPUB/XPS/MOBI fixture exists in the repo, so those were not exercised on any platform's test suite |
| Launches instantly; Linux resident mode | 26.6.17-1 | ✓ | ✓ (resident) | **PARTIAL** | Lazy restore pinned (`tabs_test`), no toolkit init, outline/thumbnails off the launch path (`spdf_win_chrome_content.h` rule 2). **Launch time on Windows has never been measured.** Resident mode is N/A-BY-DESIGN: plan §3 reason 1 (Win32 empty-window floor is single-digit ms; the resident process was GTK's cure) | Measure before claiming |

### Files, printing & updates

| Feature | First shipped | macOS | Linux | Windows | Evidence / where the original lives | Notes |
|---|---|---|---|---|---|---|
| Open a file: Cmd+O native picker (starts in the document's folder), Open in New Tab, drag & drop, `+`, bare launch shows an empty window | 26.6.17-1 / 26.8.31-1 | ✓ | ✓ | **PARTIAL** | Code: `spdf_win_menu_open_dialog` (IFileOpenDialog, FOS_FORCEFILESYSTEM), `WM_DROPFILES` (`DragAcceptFiles`, `dispatch_drop`), `chrome_open_wide` selects an already-open path; `+` → NEW_TAB pinned by `chrome_input_test`; empty window `488e983bf`. **Unverified**: no automated or recorded live run of the dialog or a drop; no start-folder policy; Open Path… and Open Recent absent | Modal dialogs cannot run on a locked workstation; a `drive-window.ps1` step should record one open |
| Show in Folder (Explorer), Copy Path, Open in browser | 26.6.17-1 | ✓ (Finder / Shenzhen Files) | ✓ | **MISSING** | GTK `win.show-in-folder`, `win.copy-path`, `win.open-in-browser` (`spdf_shortcuts.c`); Windows = `SHOpenFolderAndSelectItems` | Shenzhen Files preference itself is N/A (below) |
| Auto-reload when the file changes on disk; read-only sources open as a silent shadow copy with a read-only dot, refreshed on change, Save As converts | 26.6.27-2 | ✓ | ✓ | **MISSING** | No `ReadDirectoryChangesW`/`FindFirstChangeNotification` in `portable/win/src`; `read_only` always 0. Port GTK `spdf_watcher_logic.c` (112, TF, `watcher_test.c`) + `spdf_watcher.c` (674); mac `SPDFMacFileWatcher.mm` (277), shadow-copy schema keys `readOnly/workingPath/roCopy*` (already carried through `session.yaml` untouched) | |
| High-quality native printing with Fit / Actual Size / Custom scaling; permission gate; 150 dpi cap without 'h' | 26.6.17-1 | ✓ | ✓ | **PARTIAL** | Done: `spdf_win_print.cpp` (PrintDlgEx, own document handle), `spdf_win_print_math.h` ← `spdf_print.c` (differential 1,944,132/0), `print_math_test`, `light_theme_test` printed sheet, Print greyed on the 'p' flag (`menu_test`). Missing: **no scaling UI** — `SPDF_WIN_PRINT_SCALING_FIT, 1.0` hard-coded (`spdf_win_chrome_commands.h:313`), `printScalingMode`/`printCustomScale` not persisted; the job itself never run end to end (needs a printer and an unlocked session, `spdf_win_print.h` header) | |
| Save As…, Save Page As… (single-page PDF), `.pdf` extension policy | 26.6.17-1 | ✓ | ✓ | **PARTIAL** | Writes pinned: `SPDFCoreSaveTests` PASS natively (MoveFileExW replace), `page_export_test` test_copy_page_writes_one_page and the naming rules. Unverified: the `IFileSaveDialog` shell (`spdf_win_export.cpp`) has never been shown by a test or a recorded run | Same interactive-verification gap as Open |
| Copy Page (single-page PDF + path), Copy Page Image, Copy Page Text | 26.6.17-1 | ✓ | ✓ | **DONE** | `spdf_win_clipboard_page.cpp`; `page_export_test` (HDROP + registered "PDF" + text composition, DIB composition, lazy scratch dir, clipboard round trip) PASS | |
| Document properties (Cmd+I): Document / Dates / File / Statistics, Copy All transcript | 26.7.9-1 | ✓ | ✓ | **DONE** | `spdf_win_properties.cpp`, `spdf_win_props_format.h` ← `spdf_props_internal.h` (differential 187,315/0), `properties_test`, `props_format_test`, `properties_dialog_test` PASS | Word count omitted, as on GTK; comment count passed as 0 until annotations exist |
| Verified daily auto-updater (kept off the launch path, hourly/day-change/wake catch-ups, release highlights, size clamp), Check for Updates…, auto-check setting | 26.6.27-1 / 26.7.17-1 / 26.8.31-1 | ✓ (Developer ID, notarization) | ✓ (minisign, deb + tarball) | **PARTIAL** | Wired 2026-09-02: `spdf_win_updater_*` (feed, store, verify, install, ui) with `spdf_win_updater_start_background` armed after the window shows and Check for Updates... on the File menu; the four offline suites pass. The install path never runs until a signed release exists and `k_spdf_win_pinned_thumbprint` is set (an empty pin fails verification by design). Was: nothing in `portable/win/src`. Verification core is portable: GTK `spdf_updater.c` (2,369; minisign/ed25519 via OpenSSL, `updater_test.c`), `spdf_update_version.c` (75, TF). Install path is Windows-specific (Authenticode + self-replacing exe or MSIX; plan §2.4). Mac `SPDFUpdater.mm` (1,583), `SPDFUpdaterDownloadBounds.mm` (TF) | Prerequisite: a published Windows binary and a release-asset layout |
| One-click default PDF reader | 26.6.17-1 | ✓ | ✓ | **PARTIAL** | `spdf_win_assoc.cpp` (HKCU ProgID, the Default Apps page) behind File > Make Default PDF Reader, `assoc_test` passes; not yet observed live. GTK `spdf_default_reader.c` (263, `default_reader_test.c`), mac `SPDFMacDefaultReader.mm` (152). Windows: `IApplicationAssociationRegistration` / Default Apps deep link; needs a ProgID and file association first (plan §2.4) | |
| Readable YAML state (`settings/session/documents/favorites.yaml`), JSON→YAML migration with `.migrated-backup` | 26.8.29-2 | ✓ | ✓ | **PARTIAL** | Done: `session.yaml` through the shared codec (`state_test` test_write_matches_the_shared_codec, `session_test` round trip; refuses to overwrite unreadable state, `silent_failure_test`). Missing: `settings.yaml`, `documents.yaml`, `favorites.yaml` never read or written; `spdf_win_state_migrate` implemented, never called from `main()` (moot — Windows never had JSON files); `bookmarks.yaml` deliberately absent (macOS security-scoped bookmarks) | |
| Menus (File / Go To / Zoom / View / Edit), Cmd→Ctrl accelerators, check marks and greying | 26.6.17-1 | ✓ | ✓ | **DONE** | `spdf_win_menu.h` one table, `menu_test` 10 cases PASS at HEAD; app menu is a popup from the toolbar `…` — no menu bar, by design (`spdf_win_menu_app_popup` note; a Win32 bar cannot be themed) | Working-tree edit in flight adds 19 ids with no handlers |
| Settings menu: Open New Documents with Side Panel / Map, Keep Image Colors, Search Jumps to Nearest, Open settings.yaml…, Reveal Settings Folder | 26.6.17-1 | ✓ | ✓ (subset) | **MISSING** | `spdf_win_state.h` can read the file; no settings model, nothing reads `defaultSidebarVisibleForNewDocuments`, `minimapWidth`, `sidebarWidth`, … (keys listed in `spdf_state_internal.h:61-95`) | Cheap once a settings struct exists |
| Keyboard Shortcuts cheat sheet (Help / F1), About | 26.6.17-1 | ✓ | ✓ | **PARTIAL** | `spdf_win_shortcuts.cpp` generates the sheet from the menu table (F1), `spdf_win_about.cpp` the About box; `shortcuts_test` and `about_test` pass; the two dialogs not yet captured live. The menu table is the data source (`spdf_win_menu.h` header); GTK `spdf_shortcuts.c` generates its sheet from the same kind of table; mac `ShenzhenMacDelegate+ShortcutHelp.mm` | |

### Platform

| Feature | First shipped | macOS | Linux | Windows | Evidence / where the original lives | Notes |
|---|---|---|---|---|---|---|
| Shenzhen Files as the automatic file manager (Show in Folder reveals there; Settings ▸ File Manager) | 26.8.27-1 / 26.8.31-1 | ✓ | ✗ | **N/A-BY-DESIGN** | macOS-only product (readme tags `macOS`; `SPDFMacFileExplorerPreference.mm`) | The Windows form is plain Explorer reveal (row above) |
| Developer ID signing, hardened runtime, notarization, DMG; "Set Up Permissions…" wizard; security-scoped bookmarks | 26.6.17-1 | ✓ | n/a | **N/A-BY-DESIGN** | Apple platform mechanics. Windows counterpart (Authenticode, installer) belongs to the updater/release row | |
| App icon, taskbar identity, `.pdf` file association | 26.8.27-1 (new icon) | ✓ | ✓ | **PARTIAL** | `spdf_win.rc`, `spdf_win.ico` and `spdf_win.manifest` are compiled into the exe; the AppUserModelID and the window icons are applied after the show (`spdf_win_about_apply_identity`, wired 2026-09-02); the ProgID is `spdf_win_assoc`'s; not yet observed live | Artwork exists in `portable/mac/Assets.xcassets` |
| Native build + headless test harness for the frontend | — | ✓ | ✓ | **DONE** | `build-native.cmd`, `run-tests-native.sh` (56 cases), six `*-differential-native.cmd`, `verify-phase1.ps1`, `screenshot-window.ps1`, `drive-window.ps1` — all exercised this audit | 8 cases permanently BLOCKED off a Mac until reference PNGs are committed (observations §7.6) |
| A published Windows binary / installer | — | ✓ | ✓ | **MISSING** | readme: "no published Windows binary" — still true | Gate for the updater and default-reader rows |

**Counts (57 rows above): DONE 17 · PARTIAL 18 · MISSING 19 · N/A-BY-DESIGN 3.**

## (a) Gap list, ranked by user impact

Each line: what · size · port from. "TF" = toolkit-free original to transcribe and differentially test.

1. **Markdown reader family** (MISSING) — 18,138 LOC to port (`portable/mac/markdown/`, `SPDFMacMarkdown*`), md4c/gumbo already portable; pagination not 1:1 by design. Largest item by far; a product decision on ordering, not a technical one.
2. **Escape closes the window** when nothing is focused (divergence) — 1 line, `spdf_win_window.cpp:354`. Fix first; it will bite every user who cancels a search twice.
3. **Search results sidebar + section switching** (MISSING) — small-medium; `spdf_sidebar_internal.h` (278, TF) → new `spdf_win_sidebar_results.h` with a differential, then `spdf_win_chrome_sidebar.cpp` rows; make the segmented control clickable in `spdf_win_chrome_input.h`.
4. **Match navigation** (PARTIAL): scroll-to-rect on the canvas, nearest-match jump (`spdf_win_search_nearest_match` already ported), type-anywhere, Ctrl+F seeds from selection, Ctrl+V paste-to-search — small; `SPDFMacFindNearest.mm` (36, TF), `ShenzhenPDFMac.mm:10425`.
5. **Minimap interaction** (PARTIAL): click-to-jump, viewport drag, wheel strip-scroll, Ctrl-wheel zoom, search markers — small-medium; geometry already in `spdf_win_minimap.h`, only routing in `spdf_win_chrome_input.h`/`_actions.h` is missing.
6. **Password-protected PDFs** (MISSING) — small-medium; GTK `spdf_password_lifecycle.c` + `_controller.c` (TF) + a Win32 prompt; install qpdf to unblock `SPDFCorePasswordTests`.
7. **Settings persistence** (PARTIAL): theme, Keep Image Colors, panel visibility/widths, nearest-search, print scaling — small; keys in `spdf_state_internal.h`, file IO already in `spdf_win_state.c`.
8. **Session fidelity** (PARTIAL): fit-mode round trip (`spdf_win_tabs_app.h:59-60`), scroll replay, `searchText`, window `frame`, coalesced periodic save — small.
9. **Recents / reopen closed / favorites / Cmd+K palette** (MISSING) — medium; GTK `spdf_palette.c` pure half (TF), `spdf_state.c` recents/favorites schema; mac `SPDFMacPaletteResults.mm` (TF).
10. **Multi-window** (PARTIAL/MISSING): New Window, detach tab → new process, cross-window reattach, drop indicator — medium-large; `SPDFMacTabStripView.mm:519-699`, `SPDFMacTabStripGeometry.h` (already transcribed).
11. **Annotations + Comments sidebar** (MISSING) — medium-large; core API exists; GTK `spdf_annot.c` (1,301), `spdf_sidebar.c`.
12. **File watcher / auto-reload / read-only shadow copy** (MISSING) — medium; GTK `spdf_watcher_logic.c` (TF) + `ReadDirectoryChangesW`; mac `SPDFMacFileWatcher.mm`.
13. **Presentation mode + Full Screen** (MISSING) — small-medium; the chrome already collapses on `model->presentation`.
14. **Page rotate** (MISSING) — small; core `spdf_rotate_page`, canvas re-measure.
15. **Printing UI** (PARTIAL): scaling choice + persistence, one recorded end-to-end job — small.
16. **Open/Save dialogs verified live**, Open Path…, Show in Folder, Copy Path (PARTIAL/MISSING) — small; record a `drive-window.ps1` run.
17. **Auto-updater** (MISSING) — large; `spdf_updater.c` verification core (TF) + Authenticode/self-replace install path; blocked on a published binary.
18. **OCR** (MISSING) — large; `spdf_ocr.c` + `spdf_toolchain.c`; needs a Windows toolchain-acquisition decision.
19. **Translation** (MISSING) — large; `spdf_translate.c`; same decision (Python/Argos on Windows).
20. **Default reader + file association + icon/taskbar identity** (MISSING) — small-medium; `spdf_default_reader.c`, an `.rc` with the existing artwork.
21. **Shortcuts cheat sheet + About + Check for Updates entry** (MISSING) — small; generate from `spdf_win_menu.h`.
22. **Render pipeline** (PARTIAL): async visible-page render, inactive-tab warm-up — medium; `SPDFMacInactivePreload.mm`, `SPDFMacLaunchWorkPolicy.mm` (TF).
23. **Regex multiline toggle** (PARTIAL) — tiny; `spdf_win_search.cpp:255`.
24. **Tab polish** (PARTIAL): same-name disambiguation (`SPDFMacSupport.mm:82`, TF), read-only dot, hover previews, unselected-tab hairline (26.9.2-1) — small.
25. **Sidebar auto-hide** when a document has nothing to list (mac `rebuildSidebar`) — tiny.
26. **Measure launch time** on Windows before the readme claims it — measurement, not code.
27. **Text-URL hover hand** (PARTIAL) — small; needs the off-thread region build both originals have (`spdf_win_links.h:14-32`).

## (b) readme claims the Windows build now satisfies but is not credited for

The readme is a release gate; these tags will need updating when a Windows build ships.

- `Incremental search with live count` <sub>macOS · Linux</sub> → add Windows (DONE; only the results sidebar is missing, which is a separate bullet).
- `Scrollbar heat-map` <sub>macOS · Linux</sub> → add Windows for the heat-map; the "remembers its query across relaunches" half is not yet true.
- `Regex & multiline search` <sub>macOS · Linux</sub> → Windows has regex, not multiline; credit only after item 23.
- `Dark reading theme, for every document` carries **no tag**, implying all platforms. It should read <sub>macOS · Windows</sub>: Linux has zero dark-theme code (plan §8, handoff §8); Windows has it minus persistence.
- `Print, Save as PDF and Copy Page always use the document's own colours` — true on Windows (`light_theme_test`).
- `Copy, search and translate text in any PDF; no "Copying is not allowed"` (26.9.1-1) — Windows honours it by construction (no gate anywhere; translate itself is missing).
- `Snappy native rendering` <sub>macOS · Linux</sub> → partial credit (pool, cache, prefetch, cancellation pinned; visible page still synchronous).
- `readable YAML state … <sub>YAML state: macOS · Linux</sub>` → `session.yaml` is byte-compatible on Windows (`state_test`); settings/favorites are not written yet.
- `MuPDF-backed C core … shared by both frontends` → three frontends.
- **Platform support: "Windows — legacy … no published Windows binary"** is now half wrong: a native Win32 + Direct2D frontend on the portable core exists (`portable/win/`, 23,308 LOC of `src/`, 14,814 of tests). "No published binary" remains true. The Build-from-source section still describes only the SumatraPDF `bun ./cmd/build.ts` path; `portable\win\build-native.cmd` should be added.
- The Linux parity list credits `properties panel`, `printing`, `command palette`, … — Windows has the first (DONE) and most of the second (PARTIAL); a Windows list in the same style would be honest and short.

## (c) Release notes and documents that contradict the tree

1. **`26.9.2-1` exists as a tag and on `origin/master` only.** HEAD has no `releases/26.9.2-1.md`, the readme at HEAD says 26.9.1-2, and `release-notes-next.md` says "since 26.9.1 build 2". Rebasing or merging `origin/master` is required before any Windows release branch, and the 26.9.2-1 Markdown/tab-outline items above assume that merge.
2. **readme "Dark reading theme, for every document"** (untagged) and **"Linux — full parity"** vs. `portable/linux/gtk4/`: zero references to `SPDF_RENDER_DARK_THEME`, `SPDF_RENDER_PRESERVE_IMAGES` or `spdf_recolor`. Linux has no dark theme and no Markdown; "full parity" overstates on both counts (plan §1 counts eight missing macOS features).
3. **`releases/README.md` "Each published release has one tracked YY.M.DD-BUILD.md file"** — releases 26.6.17-1, 26.6.25-1, 26.6.27-1/-2 and 26.7.9-1 have no file; the archive begins at 26.7.17-1. Their feature claims live only in commit bodies (the 26.7.9-1 body is the sole record of the properties panel, nearest-match jump and middle-click close).
4. **Three overlapping notes for one Markdown release**: `26.8.27-1.md` ("native read-only presentation", "Cmd+W … Ctrl+W"), `26.8.28-1.md` ("paginated A4 sheets") and `26.8.29-2.md` describe the same feature set three times with different claims (26.8.27-1 says pagination "keeps headings with following content", 26.8.29-2 describes a full redesign). The git log shows 26.8.28-1/-2 and 26.8.29-1/-2 release commits whose titles were rewritten; which build actually shipped which behaviour is not recoverable from the notes.
5. **Stale defaults in code comments**: `portable/mac/SPDFMacMarkdownSession.h:34` and `portable/mac/markdown/SPDFMarkdownPaginator.h:38` still say Keep Image Colors defaults to NO; 26.9.1-1 made it YES (flagged by the handoff, still present at HEAD).
6. **`portable/win/README.md`** still says "nobody has seen a ShenzhenPDF window open", "20 cases, 0 failed", "5,021 committed lines", ARM64 guest via Parallels, "Only three of the six core suites are wired". All superseded: 56 cases, ~23k LOC, x64 native, seven core suites registered. Its "What is and is not proven" section is now wrong in the direction that matters (the window has been seen).
7. **`windows-native-observations.md`** is internally inconsistent after later edits: §2.1 still lists Find, menus, Open, selection, links, printing as missing (all landed in `099a68508`, `86ae70cf3`, `e8cba79fa`); §7 item 1 strikes Find as done while item 2 still asks to port it; §8 says "33 cases" (now 56); §3 says "37 cases … 8 blocked".
8. **`portable/docs/windows-captures/README.md`** reproduction says `SPDF_FIND_QUERY=fixture` drives the search — that environment bridge was deleted (`spdf_win_main.cpp` header: replaced by the `--find` flag). The instructions no longer reproduce the pictures.
9. **`windows-port-handoff.md` §1.4** (the original ledger) and **`windows-port-plan.md` §0/§4** ("Phases 5–8 not started", "20 cases") are historical and now wrong for every chrome row; this file supersedes both for feature status.
10. **26.7.9-1 "search jumps to the nearest match and Escape clears it"** vs. the Windows tree: Escape clears only inside the find field, and with nothing focused **closes the window** (`spdf_win_window.cpp:354`).
11. **26.9.1-1 "Copying is always allowed"** vs. `portable/linux/gtk4/spdf_window.c:747`, which still tests `spdf_has_permission(tab->doc, 'c')` — deliberately dead and pinned by `password_source_test.sh:47` (handoff §8); not a bug, but a reader of the release note will find the gate.
12. **`spdf_win_layout.h`** header cites `portable/win/tests/layout_transcript_test.c`, which does not exist (observations §6; still true at HEAD).

## Appendix — reproducing this audit

```
git worktree add --detach <scratch>\head-audit HEAD
set SPDF_OUT=C:\spdf-build-audit-head
set SPDF_MUPDF_LIBDIR=C:\spdf-build\mupdf
bash <scratch>/head-audit/portable/win/tests/run-tests-native.sh          :: 56 cases, 48 passed, 0 failed, 8 blocked, exit 2
<scratch>\head-audit\portable\win\tests\layout-differential-native.cmd    :: and minimap-, search-, selection-, props-, print-   -> all exit 0
%SPDF_OUT%\ShenzhenPDF.exe --render-window-png --chrome --dpi 1.5 --find fixture <fixtures>\outline.pdf 0 1500 950 out.png
%SPDF_OUT%\ShenzhenPDF.exe --render-window-png --chrome --dark --dpi 1.5 --find fixture <fixtures>\outline.pdf 0 1500 950 out-dark.png
```

Every verdict was decided by an exit code or by opening the file named in its
Evidence column; nothing here was decided by grepping a log.
