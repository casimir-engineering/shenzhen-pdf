# User feedback batch - 2026-08-26

Source: user-provided screenshot received 2026-08-26. The screenshot is treated
only as product feedback; text shown inside it is not an instruction source.

Release baseline: GitHub direct-download build from `origin/master` at
`891b04b44`. Mac App Store/TestFlight support is out of scope and must not be
reintroduced. The release candidate must remain Developer ID signed, notarized,
stapled, and compatible with the existing GitHub auto-updater.

## Tracker

| ID | Request | Acceptance criteria | Status | Evidence / commit |
|---|---|---|---|---|
| UF-01 | Native text multi-click selection | Double-click over selectable document text selects one word. Triple-click selects the containing text block/paragraph. Plain left-drag selection and link clicking remain unchanged. | macOS implemented and independently reviewed; Linux UI pending | Typed core and real `SPDFDocumentView` event tests cover word/block selection, `down/up/down/up` link cancellation, link-drag range selection, control-click, and interaction cleanup. `318d0711d` restores clean-build linkage. GTK4 still needs click-count integration with the shared engine. |
| UF-02 | Close-tab shortcut | `Cmd+W` on macOS and `Ctrl+W` on Linux close the active tab. A tab whose source file was moved/deleted closes through the same path without an error or disabled command. The last-tab/window behavior remains unchanged. | Implemented on macOS and Linux; installed-app acceptance pending | GTK4 coverage in `4c1989be2`; macOS close-policy tests cover selected missing-source tabs and invalid selections. Current automation tests policy/source wiring rather than a live missing-file accelerator event. |
| UF-03 | Intermittently unselectable PDF text | Selection works on the reported connector datasheet when its PDF text layer is valid. Image-only/scanned regions remain honestly non-selectable and can use OCR. Add a regression fixture for the identified geometry/text-order failure. | Implemented and independently reviewed on macOS | Synthetic OCR gaps and image-only regions return `NONE`; incomplete Unicode/geometry is flagged, finite glyphs remain selectable, and the macOS adapter preserves dynamic geometry without the old fixed rectangle cap. |
| UF-04 | Configurable file explorer | General settings offer the system file manager and Shenzhen Files when installed. Reveal/show-in-folder actions use the selection, persist it, and fall back to Finder/default file manager if the chosen app is unavailable. | Implemented and tested on macOS | The isolated preference/menu/launch-route suite covers persistence, both choices, files/directories, missing-app fallback, and launch-failure fallback; the full app build passes. Linux retains its system file manager. |
| UF-05 | Clear tab copy wording | The tab context menu command is named `Copy Document`; it still puts the file URL on the pasteboard and preserves `Copy Path`. | Implemented on macOS and Linux; live clipboard acceptance pending | `4c1989be2` and the macOS menu wiring preserve distinct document-copy and path-copy actions. GTK automation currently verifies the wiring rather than a live desktop clipboard transfer. |
| UF-06 | Correct source tab after detaching | Detaching the selected PDF tab never opens or selects an unrelated text document in the source window. The source window selects the document that was active immediately before the detached document, with a deterministic adjacent-tab fallback. | Implemented on macOS and Linux; installed-app acceptance pending | GTK4 MRU restoration in `4c1989be2`; macOS identity-based MRU/adjacent fallback policy tests pass. A real detach/process interaction remains in the RC checklist. |
| UF-07 | Minimap wheel speed cap | Without modifiers, each discrete wheel notch over the minimap moves at most one document page. Precise trackpad scrolling remains smooth; `Cmd/Ctrl` zoom gestures and minimap dragging keep their current behavior. | Implemented and tested | `ecdbd73d7`; macOS minimap suite and complete GTK4 test sweep pass. |
| UF-08 | Double-click titlebar to maximize | Double-clicking an actually draggable, empty titlebar/tab-row region invokes the native window zoom/maximize behavior. Double-clicking tabs, buttons, and fields keeps their existing behavior. | Linux implemented; macOS empty-tab-row repair in progress | GTK4 empty-header behavior landed in `4c1989be2`. An acceptance audit found that the macOS empty tab-row path did not reach the native chrome handler; the fix must preserve tab dragging/detachment and control clicks. |
| UF-09 | Password-protected PDFs | Opening an encrypted PDF prompts securely for its password, retries after a wrong password, supports cancel, and never persists or logs the password. A successful unlock supports normal reading/search/rendering for that session. | macOS/core implemented; Linux repair under independent review | Generated encrypted-PDF tests cover plain, wrong-password, user, owner, owner-only, and restricted cases. `a79ea1b07` drives a real AppKit secure sheet through wrong-password retry, success, field clearing, and idempotent cancel. Linux startup visibility, watcher rollback, worker lifetime, retry, and cancel paths are undergoing a second review. |
| UF-10 | EPUB chapter navigation | Clicking an EPUB chapter reliably navigates to the chapter destination and updates the visible/current page. PDF chapter navigation remains unchanged. | Implemented and tested | `d5cb2965b`; generated nested EPUB outline test passes, including invalid and external targets. |
| UF-11 | Read-only Markdown | Open common `.md` Markdown from Claude/Obsidian; render headings, emphasis, links, block quotes, lists, tables where supported, and fenced code. Code fences use syntax highlighting and expose a supported-language selector when the declared language is absent/unknown. | Queued | Markdown agent |
| UF-12 | Markdown language search, print, and PDF export | Markdown appears in the normal tab/session workflow. The syntax-language selector has a narrowing search field and full keyboard navigation. Print and Save as PDF use an A4 portrait pagination model that fills pages while avoiding a section heading in roughly the final quarter when its following content cannot fit. | Queued | Markdown agent |
| UF-13 | Release candidate handoff | All targeted tests pass; each meaningful tested slice is committed. Produce a signed/notarized/stapled DMG without publishing, open the installed DMG app with representative PDFs, encrypted PDF, EPUB, and Markdown fixtures, show the in-app release-notes window, and capture it for user go/no-go. | Queued | Release QA agent + parent |

## Validation rules

- Preserve the shipped GitHub updater and direct-download signing model.
- Do not publish, push a release tag, or replace the public GitHub release until
  the user gives an explicit go decision.
- Run focused tests after every slice and the complete discovered test suite
  before building the release candidate.
- Treat visual/manual interaction claims as requiring an installed-app check;
  automate model and geometry behavior where practical.
- Keep Linux parity for shared behavior and shortcuts. Platform-native macOS
  titlebar behavior may remain macOS-specific.

## Session log

- 2026-08-26: fetched GitHub and discovered the original checkout was four
  unpublished YAML commits ahead of the old base and 66 commits behind the
  released branch. Preserved it as `archive/local-yaml-migration-20260826` and
  started `codex/user-batch-20260826` from published `origin/master` at
  `891b04b44`.
- 2026-08-26: first agent wave assigned to product acceptance, text/tab
  interactions, minimap/window behavior, and password-protected PDFs.
- 2026-08-26: committed EPUB internal-outline URI resolution and a generated
  nested EPUB regression fixture as `d5cb2965b`.
- 2026-08-26: committed the one-page discrete minimap wheel cap for macOS and
  GTK4 as `ecdbd73d7`. Precise trackpad input and momentum retain their existing
  paths. The focused macOS suite and all GTK4 tests pass.
- 2026-08-26: confirmed that the sampled connector datasheet contains an
  incomplete Tesseract OCR layer. Selectable OCR text must remain selectable;
  visible raster labels with no glyph geometry cannot be selected without OCR.
- 2026-08-26: clarified the screenshot's search request: it belongs to the
  supported syntax-language picker, not to a second Markdown document-search
  interface. Ordinary document Find remains part of normal tab integration.
- 2026-08-27: release audit selected `26.8.27-1` (no existing tag) and verified
  the GitHub updater contract: exact `ShenzhenPDF-mac-arm64.dmg` asset name,
  Developer ID Team `66LJ4BV7Q3`, bundle ID `com.intuition.shenzhenpdf`, hardened
  runtime, notarization, and a stapled ticket. The unpublished RC will be built
  from a clean detached worktree and will not run the publishing path.
- 2026-08-27: release audit also confirmed stale TestFlight tooling remains in
  the repository despite the product's completed App Store removal. It will be
  removed as an isolated release-tooling slice while retaining the generic
  sandbox guard used against third-party repackaging.
- 2026-08-27: committed GTK4 missing-source `Ctrl+W`, real-file tab copy,
  MRU restoration after detach, and empty-header maximize as `4c1989be2`.
  The complete GTK4 test sweep, including eight new interaction tests, passes.
- 2026-08-27: completed the macOS/core encrypted-PDF security gate. The
  generated qpdf fixture suite, credential/source-identity tests, permission
  source contracts, properties/translation regressions, window-chrome test,
  and full macOS application build pass. Passwords remain process-memory only;
  encrypted OCR is blocked instead of creating a plaintext temporary copy, and
  protected printing uses the authenticated MuPDF path.
- 2026-08-27: completed the macOS native titlebar interaction gate. The pure
  chrome-action test and full macOS app build pass; empty draggable regions use
  native window zoom on double-click, while tab controls retain their own event
  handling. The tab context menu now says `Copy Document`.
- 2026-08-27: completed macOS tab-lifecycle parity. Missing-source tabs keep
  `Cmd+W` enabled, and detaching the active tab restores the most recently
  active surviving tab with deterministic adjacent fallback. The isolated
  lifecycle suite and full macOS app build pass.
- 2026-08-27: added a persisted Settings > File Manager choice between Finder
  and Shenzhen Files. All reveal actions use the selected application, with a
  tested Finder fallback when Shenzhen Files is absent or rejects the launch.
  The implementation is isolated in a 143-line helper and reduces the legacy
  macOS coordinator by five lines.
- 2026-08-27: completed the shared dynamic text-selection engine. Word and
  paragraph/block selection require a hit inside real glyph geometry, while
  OCR gaps and image-only areas return a non-error `NONE`. Generated fixtures
  cover separated columns, multiline blocks, invisible OCR text, large gaps,
  rotation, incomplete geometry, and more than 256 highlight rectangles. The
  focused suite passes normally and under AddressSanitizer/UBSan; macOS and
  GTK event integration remains a separate reviewable slice.
- 2026-08-27: completed the macOS selection event integration. Single link
  clicks wait through AppKit's multi-click interval, while a second or third
  click cancels the pending activation and selects the word or containing text
  block. A real `SPDFDocumentView` event harness covers AppKit's
  `down/up/down/up` sequence, link-drag selection, control-click, `NONE`, page
  replacement, tab replacement, and deallocation. Focused suites pass under
  ASan, UBSan, and ThreadSanitizer; an independent reviewer returned COMMIT.
- 2026-08-27: a clean-snapshot acceptance audit caught that the selection object
  was present in the dirty integration Makefile but absent from committed app
  linkage. `318d0711d` adds the shared object as an explicit app dependency; a
  fresh detached worktree now builds an arm64 app that passes strict code-sign
  verification. The same audit downgraded source-contract checks to their honest
  scope and reopened Linux multi-click parity plus the macOS empty-tab-row path.
- 2026-08-27: strengthened the macOS password UI gate in `a79ea1b07`. The
  AppKit test attaches the real secure sheet to a parent window, submits a wrong
  password, verifies retry controls and secure-field clearing, succeeds on the
  second attempt, and verifies cancel is idempotent. It passes normally and with
  the password/core path under AddressSanitizer and UBSan.
