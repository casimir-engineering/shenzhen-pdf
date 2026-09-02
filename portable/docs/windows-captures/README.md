# Windows captures

The first screenshots of a ShenzhenPDF window on Windows.

Until 2026-09-01 there were none, and there could not be: the port was built
from a macOS host driving a Parallels VM through `prlctl exec`, which runs as
`nt authority\system` and has no interactive desktop. Every visual claim in this
repo was a build, an exit code, or an offscreen render — `windows-port-handoff.md`
§0 states it plainly: *"Nobody has ever seen a ShenzhenPDF window open on
Windows."* These are the counter-evidence, and they are the Windows counterpart
to `portable/docs/gtk4-captures/` and `portable/docs/linux-captures/`.

| file | what it shows |
|---|---|
| `01-window-light.png` | The light window at 1500×950 on a 144 dpi (150%) display |
| `02-window-dark.png` | The same, `--dark` |

Both are **live windows** captured with `portable/win/screenshot-window.ps1`
(`PrintWindow` with `PW_RENDERFULLCONTENT`), not offscreen renders.

## What is in them, and why each thing is worth seeing

Tab strip, toolbar, Chapters sidebar, page canvas and minimap — the macOS layout,
with every metric transcribed from `ShenzhenPDFMac.mm` and cited to its line.
Beyond the arrangement:

- **The chapter list is the document's real outline**, and it carries
  `Überblick mit Umlaut` and `第一章 CJK section`. That is not decoration: this
  machine's ANSI code page is 1252, and a narrow UTF-8 conversion mangles both
  silently. Seeing them render correctly is seeing `MultiByteToWideChar(CP_UTF8, …)`
  being used everywhere it must be.
- **The minimap thumbnails are real page renders**, produced on a worker pool and
  never on the paint path.
- **The search highlight keeps its colours in both themes.** Yellow fill, red
  active ring, identical in light and dark — because a highlight is a mark *on* a
  surface, not a surface, and has to read over white paper and over `#1E1E1E`
  alike. The reading theme changes around it and it does not move.
- **The scroller carries the search heat-map**, the same relationship macOS has.
- **Dark is a luma remap, not an inversion.** Light ink on dark paper with the
  page's own structure intact, and the window frame follows via
  `DWMWA_USE_IMMERSIVE_DARK_MODE`.

## Provenance, and one rule for adding to this directory

Both were opened from `portable/win/tests/fixtures/outline.pdf` — a repo fixture,
deliberately. **A screenshot of a real document shows its filename in the tab
strip, and a full path shows the user's home directory.** An earlier candidate
for this set was rejected for exactly that: it was the better picture, taken on
an 86-page scan at real scale, and its tab read
`C:\Users\<name>\Documents\…`. Use a fixture, or crop, or do not commit it.

## Reproducing

```
portable\win\screenshot-window.ps1 -Exe <exe> -Pdf portable\win\tests\fixtures\outline.pdf ^
    -Out 01-window-light.png -Width 1500 -Height 950 -SettleMs 4000
```

`SPDF_FIND_QUERY=fixture` in the environment drives the search shown here; it is
a temporary bridge that disappears once the find field is typeable, and it is
documented as temporary at its definition.

**The workstation must be unlocked.** A locked session is not composited, so
`PrintWindow` returns black for a Direct2D client area and the capture looks
exactly like an app that painted nothing. `screenshot-window.ps1` detects this
and exits 68 rather than producing that picture; see
`windows-native-observations.md` §4.6, which exists because the false positive
was convincing enough to be believed once.
