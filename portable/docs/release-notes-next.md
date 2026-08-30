# Release notes

User-facing notes for changes merged since the last release (26.8.29 build 2).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Mermaid, js-sequence and flowchart.js code fences now draw as real
  diagrams — flowcharts, sequence diagrams, pie charts, state and class
  diagrams, and gantt charts — rendered natively, with no web engine and no
  network. A fence the renderer does not understand keeps its ordinary
  syntax-highlighted code box.
