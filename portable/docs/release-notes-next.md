# Release notes

User-facing notes for changes merged since the last release (26.7.17 build 1).
When cutting the next release, use this section as the GitHub release body
(the in-app updater shows it as plain text) and clear it afterwards.

## Next release

### Navigation
- Scrolling over the document map now scrolls the map strip itself, and the
  document follows at the strip's scale — a flick traverses the whole
  document, momentum included. Cmd/Ctrl-scroll zoom, click-to-jump, and
  dragging the viewport are unchanged.

### Updater
- The silent daily update check stays alive in a continuously-running app:
  an hourly background timer plus day-change and wake-from-sleep catch-ups
  re-run the once-a-day gate, so sessions kept open for days keep checking.
  Still at most one check per day across all windows.

### Interface
- Shortcut help: key labels are now vertically centered inside their
  keycaps.
