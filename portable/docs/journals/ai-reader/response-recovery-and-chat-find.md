# Response recovery and exact chat search — 2026-10-10

## Reported conversation

Inspected **what is the max actuator distance of this switch (to size a hole in
a case)?**. The stored history ends after seven render_page calls (three whole
pages, four crops) without an assistant answer. The raw failed provider response
was not retained, so the exact response shape for that request cannot be proven.

The transport collapsed null-content reasoning responses, provider errors inside
HTTP 200, and unsupported content-block shapes into one “unreadable response”
message. It also ignored finish_reason, allowing truncated actions to reach the
session and empty-string replies to appear successful. OpenRouter documents
that reasoning shares max_tokens with visible output; the previous 4096 budget
could be exhausted before an answer:
https://openrouter.ai/docs/guides/best-practices/reasoning-tokens

## Changes

- Normal allowance is 8192 tokens. A length-truncated response is rejected and
  retried once at 16384 with exactly the same model, input, tools and privacy
  policy. No tool from the truncated reply is executed. Stop cancels either
  request; no third attempt or silent model switch occurs.
- Text content blocks are normalized. Empty answers, refusals, provider failures
  and malformed envelopes have separate messages. Private reasoning/provider
  text is not exposed. The session cannot save a blank successful reply.
- The general prompt uses the user's stated purpose to choose the measurement:
  clearance asks for the moving part's swept envelope, not merely travel. No
  document-specific dimension is embedded in the prompt.
- Chat find reveals the exact rendered glyph and highlights every occurrence,
  with stronger highlighting on the current one. Return/Shift-Return move among
  matches. Navigation waits for text layout and prevents queued follow-bottom
  scrolling from hiding the match. Clearing/changing query cancels stale jumps.
  Opening a content match from history also reveals its passage; title-only
  matches open the full chat. Work is local to an explicitly searched chat,
  with no AI request or disk write.

## Verification

Offline transport tests cover reasoning-only truncation, repeat exhaustion,
partial tool batches, text blocks, provider errors, refusal, empty response and
Stop during recovery. The updated tests fail against the previous transport
(13 assertions); the fixed transport and session tests pass.

Native offscreen chat tests verify actual glyph rectangles within the viewport,
including two matches thousands of characters into a message, next/previous
navigation, existing old-message search, and highlighting. Reader acceptance,
launch-work policy and updater tests pass. No running user app was launched,
quit or captured. Live provider behavior remains unverified: the standalone
probe cannot access the saved Keychain credential noninteractively.

## Shorter default answers

The user confirmed that the latest answer was acceptable but too long. Replaced
765 words of general chat instructions with 193 words (including the language
suffix). The default is now 1–3 short sentences containing the answer, citation,
and essential qualifications. Detailed reasoning, derivations, tables and extra
suggestions require an explicit request. Retrieval stops once evidence suffices.
The prompt still preserves source honesty, language overrides, reversible tool
actions, plain chapter titles and untrusted-document boundaries. No answer value
or document-specific example is embedded. Chat session/request tests pass,
including a prompt-size ceiling and checks that the brevity rule reaches the
provider request. This checks wiring, not a guarantee of live model compliance.
