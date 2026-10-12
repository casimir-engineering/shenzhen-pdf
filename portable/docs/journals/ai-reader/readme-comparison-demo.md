# README comparison demonstration — 2026-10-12

Replaced the page-count example with a scripted comparison of two fictional
support plans: 24 versus 18 months, with repairs excluded from the longer plan.
The native chat shows citations to both documents and a pastel **24 months**
answer card labeled **Extended advisory · repairs excluded**, with **View evidence**.
The source page remains visible alongside the answer. The caption explicitly
identifies the conversation as scripted; this is a UI demonstration, not a new
model benchmark or a claim that the model produced this particular answer.

The README now leads with that image, document AI, native Markdown diagrams/math/
code, search and the map, Collection recovery, and groups. Detailed controls are
expandable; setup and engineering/platform information follow the feature tour.
The benchmark link and AI privacy/accuracy limitations remain accessible.

## Reproduction and verification

- Added `mac-ai-readme-probe` and a focused fictional fixture in
  `portable/mac/tests/SPDFMacAIReadmeProbe.mm`; reuses the production reader and
  chat/card components. The existing workspace probe entry point is conditional
  only for this reuse, and its page-count assertion now uses the actual fixture
  PDF count instead of assuming three pages. No runtime app code changed.
- Probe build/run exited 0 with zero failures: valid saved conversation reload,
  evidence button presence and exact source URL forwarding, source page count,
  usable reader layout and no visible windows. No provider requests or credentials.
- Visually inspected the native PNG and a browser preview rendered through GitHub's
  Markdown endpoint. All preview images loaded, sections appeared in the intended
  order, and there was no horizontal overflow. All local README link targets exist.
- File-size ratchet and `git diff --check` passed.
- The broader `mac-workspace-probe` exited 1 with 24 icon-contrast/native-click
  assertions. A separately compiled **unchanged HEAD** version also exited 1 with
  exactly the same 24 assertion messages and multiplicities. These are existing
  failures in this environment, not a passing suite; no extra failures were
  introduced by the fixture reuse. Logs remain at
  `/tmp/sz-readme-workspace-check.log` and
  `/tmp/sz-readme-probe-baseline-run.log`. The dedicated new probe log is
  `/tmp/sz-readme-comparison-build.log`.

This documentation update does not rebuild, replace or republish the released app.
