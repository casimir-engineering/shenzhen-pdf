# Brief answer cards

## Design

Intent: let a reader take one result from a document and immediately inspect its
source. Domain: result, unit, range, citation, passage, conversation. Color world:
paper white, reader charcoal, annotation mint, tab lavender, selection blue. The
signature is a large answer paired with a verified source action inside the chat.
Reject dashboard metrics, celebratory decoration and extra toolbar controls.

Hierarchy: 12-point medium label, 32-point semibold value, 12-point semibold source
button. Use the system font and a 16-point horizontal inset. A mint surface with
dark green text gives this answer a distinct focus inside the neutral transcript.
Corners are 10 points; the 28-point evidence button reuses the reader's reliable
full-bounds tracking class, with a quieter green tint, focus ring and no bitmap
icons. Light/dark variants preserve contrast. Long values wrap rather than clip;
height is measured from text layout. Text remains selectable and chat-searchable.

## Implementation

The session exposes `present_answer` only in document chat. It validates bounded
plain-text label/value and an exact tool-issued citation. It records the tool
result plus an ordinary assistant message carrying local card metadata, then
completes immediately. No continuation request or duplicate prose is needed.
Optional automatic chat-title generation follows its existing policy. History
stores/searches the plain-text answer; provider replay strips local presentation
metadata. Invalid cards return a tool error so the model can correct or use prose.
The view only renders validated cards and routes evidence through existing source
revision/layout checks. There are no document mutations or new startup jobs.

## Verification

Chat/session tests cover tool discovery, inert construction, evidence validation,
completion without another answer round, persistence, history search and clean
provider replay. The previous session fails six new checks. Production-linked
reader acceptance tests pass. Offscreen native chat probes cover light/dark,
minimum widths, long labels/values, all button corners, exact citation callbacks,
search highlights and reopening the chat. Native PNGs were visually inspected;
there are no overlaps or clipped values. User app was not launched or captured.
Live model selection of the new tool remains unverified; the transport/session
path is exercised with a deterministic fake model.
