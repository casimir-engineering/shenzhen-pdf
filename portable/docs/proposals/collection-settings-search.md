# Collection settings and search — design proposal

23 September 2026. Interactive mockups only; no application behavior changed by this proposal.

## Requested changes

- Put Collection settings in a dedicated **Settings** destination in the left sidebar.
- Show the current storage path, initially `~/Library/Application Support/ShenzhenPDF/Collection`.
- Use **Set location** and **Open location** as the folder actions.
- Show each search result with a document thumbnail on the left and contextual text matches on its right. Highlight the query and identify the page and saved version.

## Storage-cap policy

The current implementation refuses captures requiring additional storage when the configured cap is reached; it does not automatically remove existing copies. A zero cap means unlimited storage.

For the proposed behavior, the user chose **Remove oldest unkept document histories**. Order histories by their most recent capture, oldest first. Remove entire eligible histories until the incoming capture fits. A history containing any version marked Keep is protected as a whole. Collection never removes the original source file.

If protected histories or an oversized incoming capture prevent the cap from being met, pause new captures and explain how to increase the cap or review protected histories. Estimate whether sufficient space can be recovered before deleting anything; do not remove histories when the incoming capture still cannot fit. Lowering a cap should show its cleanup consequences before applying the change.

## Location and search behavior

Set location selects a destination and moves the existing Collection, retaining the old location until the copy is verified. Open location reveals the current Collection folder. In the mockup, both flows are simulations and do not modify or reveal files on this Mac.

Search distinguishes the latest saved copies from older versions. A hit identifies its version and page; selecting it changes the thumbnail/preview to that page. Matching text stays highlighted within complete words and readable context. Additional matches can be expanded without losing the document grouping.

Sidebar selection, search scope, layout preferences and applied Collection settings should survive app relaunch. Merely opening Settings must not apply pending changes.

## Review

An independent UX designer and Astra critic completed two review rounds within the four-round limit: **7.8/10 → 9.2/10**. The final review leaves no major or medium findings within the mockup scope.

- [Round 1 — findings](collection-settings-search-review-round-1.md)
- [Round 2 — acceptance](collection-settings-search-review-round-2.md)

Browser validation covered dark and light appearances, 1024/736/390-pixel viewports, contextual and title-only results, empty results, expanded matches, version identity, keyboard preview entry/return, navigation state, and applied settings after reload. Cleanup cancellation, protected capacity, unlimited storage, and post-cleanup location totals were checked using simulated data. JavaScript syntax checks passed and no browser console errors were observed.

The first review exposed misleading title-only snippets, lost keyboard focus, offscreen narrow previews, and stale location totals. The revised design addresses each: title matches have a separate saved-copy action; version and context are accessible; previews appear beside their result in narrow layouts and reveal themselves after layout settles; all storage views use the same simulated state.

These are interactive design proposals. Automatic cleanup, location migration, and the new native search layout have not been implemented by this design task.

![Contextual search matches beside each document thumbnail](assets/collection-mockup/final-search-dark.png)

![Settings in the left sidebar, with storage policy and location controls](assets/collection-mockup/final-settings-dark.png)
