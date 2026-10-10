# Chat activity and question visibility

2026-10-10. Implementation verification, not an independent review of my own changes.

The chat view now shows a semibold activity heading and a separate current-tool or
error detail. It consumes the session's typed Thinking, Working, Completed, Error,
Stopped and Idle states. Completed says “Complete · Ready for your reply”; this
does not infer an outstanding question from punctuation. An active task also has
a native progress indicator, while Stop remains available.

The latest user question stays in a selectable, height-limited context strip
above the newest-first transcript. Its full text remains in the transcript and
hover description. Same-count message replacements invalidate the view's cache,
so correcting a transcript cannot leave stale text onscreen.

Two native symbol buttons send `pinApp` and `pinAll`. The host applies mutually
exclusive modes through `setPinMode:` (0 normal, 1 above ShenzhenPDF windows,
2 above all windows). Selected fill/outline and mode-specific hover explanations
make the state visible. Explicit symbol palette colors preserve dark-mode contrast;
aspect fitting retains the vector symbols' native width-to-height ratio.

Validation: `make -C portable build/SPDFMacAIChatViewTests` followed by
`portable/build/SPDFMacAIChatViewTests` exits zero. The suite checks native button
corner hit targets and mouse down/up dispatch, pin selection, activity states,
latest-question visibility, same-count transcript replacement, exact citation
URLs, native citation glyph hit testing and text-view delegate routing. It also
checks transcript/composer geometry at the standalone window minimum of 520×400.

Saved native render evidence is regenerated under `/tmp/sz-ai-chat-` with names
`question`, `thinking`, `error`, `pin-app`, `pin-all`, `NSAppearanceNameAqua` and
`NSAppearanceNameDarkAqua`. I inspected these for clipping and contrast. The
window stays offscreen; this verification makes no network request and launches
no user app. Session persistence and actual window-level behavior belong to the
parallel session and standalone-window acceptance work.
