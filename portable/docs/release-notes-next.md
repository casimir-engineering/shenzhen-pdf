# Release notes

User-facing notes for changes merged since the last release (26.9.15 build 1).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Organize tabs into persistent colored groups. Collapse groups, rename them,
  choose from a larger palette, and drag a group by its left handle to reorder
  it or move it to another window. Group and document positions survive relaunch.
- Selected tabs use stronger contrast, with rounded tinted boundaries showing
  which documents belong together.
- Markdown tables keep short columns readable. Documents can specify paper
  size, orientation, margins, and explicit page breaks for reading and export.
- Open Markdown in your preferred editor from the tab or document menu;
  the chosen editor is remembered and can be changed in Settings.
- Right-click Copy Page and Copy Page Image use the page under the pointer.
- An optional agent interface inspects documents, exports page previews, and
  opens PDF or Markdown at a page or highlighted passage. It runs only when
  invoked; see [setup and commands](agent-interface.md).
