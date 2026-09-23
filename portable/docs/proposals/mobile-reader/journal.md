# Mobile design journal · 24 September 2026

## Scope and sequence

The prior desktop performance/release work was complete before this design task began. A separate creative technical director developed the mobile direction; an independent critic reviewed the specification before reviewing mockups. Root integrated the contracts, built the browser document and exercised the prototype in the Codex browser. No desktop app was launched or modified for this proposal.

## Decisions and reasons

1. **Reading and organization are separate.** A single-document reader avoids squeezing desktop tabs onto a phone. Groups remain persistent workspaces on their own screen. Browsing a group does not switch the document.
2. **The weapon wheel switches documents.** Six stable positions and a neutral current document support spatial memory. A center-arming corridor avoids accidental selection while moving up from the launcher. A normal tap list is the complete accessible alternative.
3. **Choose a familiar UI development loop, then prove the native seams.** React Native/Expo/TypeScript provides shared components and browser scenarios; native PDF/EPUB adapters must demonstrate fidelity and performance early. HTML mockups are interaction designs, not the future production shared UI.
4. **Make savings measurable.** Fixed 1 MiB blocks are the initial simple exact storage format. A preregistered mixed corpus compares total storage against whole-file content-addressed storage. If the target fails, evaluate maintained content-defined chunking or narrow the claim. No guaranteed EPUB recompression savings.
5. **Separate durable bytes from source truth.** A complete capture can be durably saved without proving that its provider stayed unchanged. Separate newest-capture and verified-recovery pointers determine default opens and history labels.
6. **One writer, explicit lifetimes.** Foreground TypeScript owns SQLite commands; native byte operations use opaque leases. Temporary handover allows at most active A and incoming B, with numeric staging/extraction bounds and reserve checks. Failed B leaves A readable.

## Review trail

| Global round | Phase | Score | Principal correction |
|---|---|---|---|
| 1 | Text | 8.37 | Navigation ownership, database writer, stale search, realistic storage benchmark |
| 2 | Text | 9.24 | Distinguish newest capture from verified recovery; reconcile handover disk budgets |
| 3 | Text | 9.44 | Preserve last verified recovery target during cleanup even with newer unverified bytes |
| 4 | Text | 9.57 | Text accepted; no unresolved major or medium findings |
| 5 | Visual | 8.64 | Repair document context, genuine 200% typography, focus, search and revision labels |
| 6 | Visual | 9.14 | Fix dark foreground inheritance, verified recovery return and row-specific export |
| 7 | Visual | 9.47 | Fix the same export identity issue in the direct unverified-only recovery action |
| 8 | Visual | 9.57 | Accepted; no unresolved blocker, major or medium findings in reviewed flows |

The complete independent reports are in `reviews/` and embedded in the browser document. Visual review follows text acceptance; final visual results are recorded there without substituting native implementation claims.

## Visual direction

Warm paper, deep green accents, serif reading samples and restrained chrome. Thumbnails anchor Collection results while text snippets remain beside them. History shows dated versions and a single Latest badge, separate from ordinary document rows.

![Reader at 390×844](prototype-evidence/reader-390.png)
![Document wheel](prototype-evidence/wheel-390.png)
![Collection direction](prototype-evidence/collection-390.png)
![History direction](prototype-evidence/history-390.png)

These initial screenshots document the design iteration, not a frozen certification of final source. Early large-text screenshots represent the initial enlarged variant; the critic correctly required a true 200% mode before final approval.

## Validation and corrections

The director's initial fixture harness recorded 21 passing checks and no JavaScript errors. Root independently used the live browser to verify PDF sample → tap switcher → EPUB sample; separate Groups; Collection query filtering and direct document opening; dated History → Return to latest; and cleanup accounting (312+48 MiB → 286+12 MiB = 298 MiB). Search location fidelity remains native-engine work; this fixture exposes sample passages only.

The live pass found a stale filtered result count, default highlighting without a query, and an older-version footer date mismatch. The visual critic additionally inspected invoking-control focus, context-menu selection isolation, per-document history identity, global search reachability and genuine 200% text scaling. These were sent back to the director as concrete corrections.

Browser evidence covers appearance, modeled navigation and DOM accessibility only. It does not prove native TalkBack, physical touch geometry, Android URI permissions, PDF/EPUB reading, storage durability, startup latency or iPhone compatibility. The specification contains separate acceptance gates for those.

## Final result

Text **9.57/10**; visual prototype **9.57/10**. Eight total independent review rounds, with text accepted before visual review began. The final pass corrected all reviewed major/medium findings; native implementation gates remain open by design. Root ran 18 focused state assertions, JavaScript syntax validation, local HTML reference validation, the repository file-size ratchet and whitespace checks. Final live-browser evidence and source hashes are in `prototype-evidence/final/`.

![Final dark reader](prototype-evidence/final/dark-final.png)
![True 200% text](prototype-evidence/final/groups-360-200.png)
![Final exact unverified export identity](prototype-evidence/final/unverified-export-final.png)
