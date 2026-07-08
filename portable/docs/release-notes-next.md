# Release notes

User-facing notes for changes merged since the last release (26.6.27 build 2).
When cutting the next release, use this section as the GitHub release body
(the in-app updater shows it as plain text) and clear it afterwards.

## Next release

### Tabs
- Middle-click a tab to close it.
- Dragging a detached tab back onto a window now shows a yellow insertion
  indicator at the drop position.

### Search
- Escape in the viewer clears the current search (query, highlights, match
  counter, and search-results sidebar).
- Search now jumps to the match nearest to your current position instead of
  the first match in the document. Toggle with Settings > "Search Jumps to
  Nearest Result" (settings key `searchJumpsToNearestResult`, default on).

### Navigation
- Cmd+K palette now lists open documents first.
- Fixed: side panel could be unavailable after opening a document from
  favorites.
- Document map now works on documents of any size (windowed lazy loading).

### Document properties
- New document properties panel (Cmd+I) with metadata, dates, file info, and
  document statistics.

### Translation
- Fixed: whole-document translate could produce invisible overlays on some
  PDFs.
- Translated overlays are now white 95%-opacity boxes with black fitted text.
- Chinese translation skips blocks without Chinese characters.
