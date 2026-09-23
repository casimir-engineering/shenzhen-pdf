---
paper-size: A4
---
# Collection implementation journal

23 September 2026 · ShenzhenPDF

**Prepared: 26.9.23-1. Technical 9.1/10 · UX 9.0/10.** No major or medium findings remain after three review rounds. All 53 release test targets passed.

## Implemented behavior

Keep local, immutable copies and history while continuing to read original documents. Search open documents, groups and Collection from one palette; recover missing originals; compare PDF and Markdown revisions in two coordinated readers.

The approved proposal is [Reader review and Collection](../../proposals/reader-review-and-collections.md). The latest visual correction is uniform title text on every tab: selection is communicated by fill, outline and weight, without fading other document names.

![Requested tab title contrast](assets/requested-tab-contrast.png)

The reference shows the problem: an inactive title fades into the gray fill. Every tab now uses the same title foreground; selected tabs retain the stronger fill and outline.

<!-- pagebreak -->

## Architecture and responsibilities

| Part | Responsibility | Validation |
|---|---|---|
| Collection store agent | Immutable snapshots, identity, deduplication, index, locking | Temporary stores; failure and laziness tests |
| Comparison agent | PDF/Markdown alignment, colored changes, paired readers | Text, image, scanned and inserted-page fixtures |
| Reader refinements agent | Tab contrast, accessibility, navigation, checkpointing | Geometry, action and state tests |
| Integration | Consent, original-path routing, search, manager, history and recovery | Build, integration tests and isolated app use |
| Independent Astra critics | Technical and UX review after implementation | Ranked findings and scores, up to six rounds |

```mermaid
flowchart TD
  O[Original document] --> R[Reader tab]
  O --> C[Background capture after consent]
  C --> S[Immutable Collection store]
  S --> I[Search index]
  S --> H[History and recovery]
  H --> V[Read-only preview]
  H --> D[Compare two versions]
  E[Edit original] --> P[Verify durable previous version]
  P --> O
```

## Decisions and actions

### 1 · Establish ownership and preserve the original

The storage, comparison and reader tasks are independent and have distinct files. Integration owns the coordinator hooks, avoiding simultaneous changes to the same large file. Collection construction and disabled-state reads must not create folders or scan documents.

A successful document open schedules a background capture. The first-use choice precedes copying. A source overwrite checks that the previous revision is durable; a full destination, revoked destination access, interrupted copy or changing source can fail even though reading the original succeeded. Normal reading remains available.

### 2 · Reuse native rendering for comparison

PDF comparison uses two native PDF reader views. Markdown first renders through the existing deterministic print plan, preserving the same pagination and selectable vector text. Alignment and differences are computed away from the UI thread. This keeps comparison separate from the editable source reader and avoids sharing mutable document handles.

<!-- pagebreak -->

## Validation evidence

### Headless checks, implementation pass

| Check | Result | What it establishes |
|---|---|---|
| Collection store / comparison / previous tab / checkpoint / reader actions / tab interactions | Exit 0 | Focused feature behavior, concurrent storage and editing failures |
| Markdown engine and UI/session suites | Exit 0 | Rendering, pagination, navigation and existing reader behavior |
| Agent commands, PDF/Markdown navigation and MCP tests | Exit 0 | Existing agent access remains functional |
| Tab state, strip style/interaction and group model/integration | Exit 0 | Persistent state and group behavior |
| Full app integration | Exit 0 | Native build, hidden-window layout, live isolated app |

### 3 · Close integration gaps before visual review

The first compilation found a category header missing its host declaration and manager actions using synthesized instance variables from another translation unit. Those were corrected without changing the storage contract. A coordinator shortcut hook accidentally matched an icon lookup with the same selector; syntax validation caught it and the hook is now limited to menu validation.

OCR receives an additional check immediately before installing its result, since the original can change while OCR runs. Locator preview and relinking have separate callbacks: previewing a candidate must never silently rebind a missing-document tab.

The coordinator is smaller after extracting palette orchestration, creating space for explicit Collection hooks without raising its size cap.

### Live validation, first integrated build

![First-use choice in the isolated app](assets/first-use.png)

The exact consent wording is displayed. Inspecting the isolated state directory before answering found no Collection folder or copied document. After Keep Enabled, the fixture was captured while its tab continued to use the original path.

![Search section order](assets/search-order.png)

Searching “orchid” returned two page matches in the open Markdown document, followed by Collection text. `col:Project` included the collected open document. The screenshot also exposed multiline snippets clipping in fixed-height rows; these are being normalized to a single line.

![Actual comparison engine output](assets/comparison-engine.png)

This is a headless rendering of test pages with the actual difference geometry, not a mockup or live-window screenshot. The red word was removed, the green word added, and the new image is outlined in green.

Cmd+Backspace returned from Design Review to Project Notes at page 2; a second press returned to Design Review. The first manager invocation revealed a missing-common-ancestor layout exception. Its constraints are being reordered, with a real hidden-window construction test added to prevent recurrence.

<!-- pagebreak -->

## Independent review rounds

| Round | Technical /10 | UX /10 | Major / medium remaining | Action |
|---|---|---|---|---|
| 1 | 6.8 | 7.0 | Technical: 2 major, 4 medium; UX: 1 major, 4 medium | Repaired; regression fixtures added |
| 2 | 8.0 | 7.2 | Technical: 3 medium; UX: 1 major, 2 medium | Queue/parser fixes; PDF ownership, thumbnail layout and archive identity |
| 3 | 9.1 | 9.0 | No major or medium findings remain | Optimized regressions and live counter retest passed |

## Release preparation

Independent reviews met the requested threshold within three rounds. Release 26.9.23-1 was prepared on `codex/collection-history-release` at metadata commit `418cb5b`. The release workflow reran all 53 test targets successfully and committed validated version metadata. No tag, push, notarization or publication was performed. The journal is delivered in the final dated build; the installed reader remains untouched.

### Review round 1 · Repair decisions

The [technical review](technical-review-round-1.md) reproduced a source-change race, unsafe overwrite during archive export and unrelated-file history merging. Capture now publishes only the fingerprint of the bytes it actually protected. Export installs only to a new destination. Observed saves have explicit identity continuity; generic opens cannot inherit a cancelled edit's pending identity. New regression fixtures also cover reference-style Markdown images, retries and mixed text/image page alignment.

The [UX review](ux-review-round-1.md) exercised the real app and scored it 7.0/10. Its main finding was that path disambiguation replaced the archive's dated title with an internal folder name. Archive identity now has its own persisted display label. The other repairs target spare tab-strip space, search routing, thumbnail captions and recovery context.

![Working Collection manager with two captured revisions](assets/manager-first-live.png)

![Review evidence: archived identity was unclear](assets/ux-round1-archive.png)

![Review evidence: thumbnail captions were missing](assets/ux-round1-thumbnails.png)

These are before-fix screenshots, retained to explain the changes. Final evidence will follow the next live evaluation.

### Technical round 2 · Queue ordering and parser fidelity

The original six technical findings are closed. A deliberately paused old capture then exposed a race with a subsequent successful save. Capture requests now have per-path generations, checked again under the transaction lock: a superseded request cannot change document identity. The regression retains one history containing both A and B. Focus-driven change detection now supplies the same explicit continuity as the active file watcher.

Asset discovery now uses the reader's actual Markdown parser. Literal code, comments and unsupported HTML cannot pull unrelated neighboring files into Collection. Only rendered image dependencies are considered. This both improves fidelity and avoids copying files that the document merely mentions as syntax examples.

### Live round 2 · Test limits made visible

The second app evaluation confirmed that indexed “Show all” search now returns both PDF and Markdown matches and that archived previews have explicit labels. It also exposed two gaps that the earlier hidden-window checks missed: thumbnail captions disappeared during live layout, and accessibility selection did not update the document actions. The thumbnail regression is being extended through layout and selection synchronization.

A PDF comparison triggered an accessibility crash in PDFKit while traversing a copied page's tagged-content tree (`CGPDFPageCopyRootTaggedNode`, recursive lock abort). This was observed in the isolated validation process, not inferred from a source review. Comparison presentation is being investigated independently; release remains blocked until the same live flow succeeds.

![Live round 2 caught blank thumbnail captions](assets/ux-round2-thumbnails.png)

An older restored archive also lost metadata after its original was renamed. The archive resolver now recognizes the original's verified filename aliases for the early schema; unknown dates are explicitly labeled unavailable instead of showing 1970.

### Candidate for round 3

Aligned comparison pages are now serialized and reopened as complete, independent PDF documents on the worker queue. A new presentation test proved the ownership defect: previously the displayed documents had no backing document reference while their pages belonged to other documents. The corrected presentation retains selectable text, annotations, blank counterparts and native accessibility. The original code fails eight ownership/serialization assertions; the new code passes. The observed live crash still requires a live retest.

Thumbnail captions now have explicit constraints. Their regression checks pixels after the run loop and layout, then verifies accessibility selection updates the details and Preview action. Archive labels are preserved in tabs, window titles and palette candidates. Existing Favorites and Actions remain available after the five requested search sections; `col:` remains limited to Collection.

![Verified search ordering and limits](assets/ux-round2-search-order.png)

![Verified group boundaries and available tab space](assets/ux-round2-groups.png)

### Round 3 follow-through · Match the production build

The technical critic independently confirmed that the shared-store race now retains one history with both versions, and rated the core implementation 9.1/10 with no major or medium findings. Edit protection publishes a durable epoch under the shared lock, invalidating older queued captures in other processes. It renews metadata without duplicating unchanged snapshots. Activation-time PDF/Markdown cache invalidation now records observed continuity only when a live cached document existed.

The live candidate then exposed an optimized-build issue in the thumbnail repair: `NSCollectionViewItem.textField` is weak. Assigning a newly created label before attaching it to a view let ARC release it early; the later constraint array contained nil and the manager crashed. The label now has a strong local owner until attached. The entire Markdown UI suite now compiles with `-O2`, matching production lifetime behavior, and still checks caption pixels and selection actions. This replaces the misleading confidence from the earlier `-O0` pass.

The Markdown integration file briefly exceeded its 500-line cap. Its checkpoint closure was extracted into a focused integration file; the limit was not raised.

### Final navigation repair

The optimized full release test sweep completed with exit 0, including all 53 discovered test targets. Live round 3 then confirmed the manager and PDF accessibility repairs. Its remaining medium finding was narrower: both comparison readers displayed the aligned appendix, but one counter still described the preceding inserted page. Navigation labels now follow the aligned destination, with deferred scroll updates guarded against stale notifications. The optimized regression verifies that both actual readers and counters reach aligned slot 3, showing old page 2 versus new page 3; it also checks independent navigation and scrolling. The pre-fix code fails four assertions in the same expanded test. The independent live retest passed: linked navigation shows slot 3 in both panes with old source 2/new source 3; unlinking permits the right pane to advance while the left remains on its blank counterpart. The UX critic closed the finding and scored the final candidate 9.0/10; the technical critic independently reran the regression and retained 9.1/10.

![Actual PDF text and image comparison after the ownership repair](assets/ux-round3-pdf-comparison.png)

![Inserted page with an explicit blank counterpart](assets/ux-round3-inserted-page.png)

![Manager captions and selected-version actions after the optimized-build repair](assets/ux-round3-thumbnails.png)

![Final live comparison counters: aligned slot 3, old source 2 and new source 3](assets/ux-round3-counters-corrected.png)

### Final evidence and remaining scope

The native inspection command rendered this journal successfully with no layout diagnostics after adding deliberate page breaks before its summary tables. Screenshots are actual app captures; the explicitly labeled engine figure is a headless render. The reviews retain their earlier failures and state where checks were live, headless or source-only.

Both critics leave only minor follow-ups: start search snippets at word boundaries, make capture reasons more specific, and add direct coordinator tests around externally edited inactive tabs. No major or medium improvements remain in their reviewed scope. The live review used isolated generated documents and state; whole-computer recovery scanning and destructive Collection deletion were covered by bounded tests rather than exercised against personal files.

### Release record

- Implementation: `daf065f0a` — Collection, comparison, navigation and regression tests.
- Visual journal and independent reviews: `77ba17824`.
- Release metadata: `418cb5b` — version 26.9.23, build 1.
- Release preparation command: `./portable/cut-release.sh --prepare-only "Collection history and persistent tab groups"`; exit 0.
- Release notes: [26.9.23-1](../../releases/26.9.23-1.md). Publication remains a separate action.

### Delivered in the reader

The final native app build completed with exit 0. Its bundle reports version 26.9.23, build 1, and passes local ad-hoc code-signature verification; this is a local validation build, not a notarized distribution artifact. The journal was opened and visually checked on page 1 in that build with its chapters, screenshots and minimap visible. The app remains open for inspection, using the isolated validation state.

![Journal open in the final 26.9.23-1 reader, with persistent groups and uniform tab-title color](assets/final-journal-open.png)
