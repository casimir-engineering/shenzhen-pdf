# Release notes

User-facing notes for changes merged since the last release (26.10.6 build 1).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Groups management has a compact Collapse all / Expand all button beside its search field. It folds document lists without switching documents, also works while filtering, and remembers the chosen expansion state.

- Group-panel controls use explicit mouse tracking so clicks reach their actions throughout each button. Collapse/expand all uses vertical compress/expand icons. A target button beside it jumps to the current document, expands its group and scrolls it into view, clearing any filter that would hide it.
