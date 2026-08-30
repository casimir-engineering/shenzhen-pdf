# Release notes

User-facing notes for changes merged since the last release (26.8.29 build 2).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Mermaid, js-sequence and flowchart.js code fences now draw as real
  diagrams — flowcharts, sequence diagrams, pie charts, state and class
  diagrams, and gantt charts — rendered natively, with no web engine and no
  network. The artwork is fully vector, so it stays crisp at any zoom and
  exports to PDF as vector shapes, and every label inside a diagram is real
  text: you can select it, Cmd+F finds and highlights it in place, and it stays
  selectable in the exported PDF. A fence the renderer does not understand
  keeps its ordinary syntax-highlighted code box.
