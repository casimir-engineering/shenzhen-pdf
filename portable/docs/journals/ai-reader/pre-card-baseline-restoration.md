# Restore the pre-card chat baseline — 2026-10-11

The user requested returning to the earlier successful chat behavior while
retaining answer cards, instead of continuing prompt tuning. The base system
prompt is restored to `d14d7c8af`, with only the original short `present_answer`
hint added. Default language and active reader context retain their existing
handling. No expected answer, drawing-specific instruction or new reasoning
setting is introduced.

Page text reads are text-only again: the later automatic sparse-page preview
is removed. The added `evidenceBasis` metadata field is also removed. Full-page
and crop inspection remain explicit `render_page` calls. The separately
requested `current_view` capability stays available as an optional tool, without
extra system-prompt guidance. Transport, page rendering and citation behavior
are not retuned as part of this restoration.

The [DeepSeek evaluation](deepseek-evidence-evaluation.md) and
[sparse-page evidence journal](sparse-page-evidence.md) record earlier experiments
and the behavior at that time; they are not descriptions of the restored
release behavior. The public assistant guide, release notes and preview notes
now describe explicit image requests and the restored baseline.

This is a baseline restoration, not evidence of improved model correctness or
speed. Live validation is still required; no new successful-answer claim is
made here. Card layout and evidence navigation have their own validation record
in [release QA](card-release-qa.md).

## Deterministic verification

An independent review confirmed that the 2,113-character base prompt matches
`d14d7c8af` byte for byte. The only added prompt sentence is the original card
hint. Page-preview source/header and metadata responses also match that commit.
Transport, reasoning preservation and citation handling were already unchanged.

Chat session, reader acceptance, analysis and chat-view tests pass. A new prompt
snapshot test fails against the preceding session source and passes after the
restoration. A sparse-page regression verifies that text reads return text and
citations without generating an image. The signed app builds successfully and
passes strict signature verification. Live model results are recorded separately.
