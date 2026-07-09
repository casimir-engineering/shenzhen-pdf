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
- Cmd+K palette now includes every menu-bar command (with menu breadcrumb,
  keyboard shortcut, and toggle state); search matches command titles and
  menu names.
- Typing "fav" (or any longer prefix of "favorites") in the Cmd+K palette
  shows all favorites.
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
- Fixed: the translated copy lost the document's chapters (outline) and
  annotations; both are now preserved, including links.
- Chapter titles and comment texts are now translated too when they are in
  the source language.
- Smarter per-item translate/skip decision: with a Chinese or Latin-script
  source language only items in that script are translated; with other or
  unknown sources the target language decides (Latin-script text when
  translating to Chinese, Chinese text when translating to a Latin-script
  language). Digits/punctuation-only items are left untouched.
