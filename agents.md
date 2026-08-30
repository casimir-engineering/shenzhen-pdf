# Working in this repository

ShenzhenPDF is a native **macOS** reader (AppKit) for PDFs and Markdown, built on a
portable C core that wraps MuPDF. A GTK4 Linux frontend shares that core. The
original SumatraPDF Win32 tree still lives in `src/` but is legacy and is not
built or shipped from here.

- `portable/core/` — platform-neutral C core (documents, rendering, search,
  selection, YAML state). Shared by both frontends.
- `portable/mac/` — the macOS app. `portable/mac/markdown/` is the self-contained
  Markdown engine (parser, renderer, paginator, diagrams, math, HTML islands).
- `portable/linux/gtk4/` — the GTK4 frontend.
- `ext/`, `mupdf/` — vendored dependencies. Do not edit vendored sources.

## Build and test

```sh
make -C portable mac-app                        # build dist/ShenzhenPDF.app
portable/mac/tests/markdown/run-tests.sh        # Markdown engine suites
portable/mac/tests/run-markdown-integration-tests.sh   # Markdown app suites
make -C portable core-outline-tests core-selection-tests core-password-tests
tools/check-file-sizes.sh                       # file-size ratchet
```

**Judge test results by exit code, not by piping into `grep`.** `script | grep -c passed`
reports *grep's* status, so a failed build can look green. Redirect to a file and
check `$?`.

Every source file has a size cap in `tools/file-size-limits.tsv`. Prefer extracting
a new focused file over raising a cap; when a cap genuinely must move, add a
`+N lines for …` justification in the same style as the existing entries.

## Conventions

- Match the surrounding code: this codebase favors explicit, deterministic data
  flow over global or ambient state (theme variants, render options and page
  configurations are threaded through explicitly, never read from app state deep
  in the render path).
- Colors used in rendered output are concrete sRGB constants, never
  appearance-dynamic, so screen, print and export always produce the same page.
- The Markdown engine's canonical-coordinate contract: the rendered attributed
  string is the only user-visible text coordinate space. Anything visible must be
  searchable and selectable through it; structural markup must never leak into it.
- Speed is a standing priority. A feature must cost nothing for documents that do
  not use it, and nothing new may run on the launch path. Prove laziness with a
  test rather than asserting it.
- Commit each meaningful, tested change set. Do not commit half-finished work.

## Releases

`./portable/cut-release.sh --prepare-only ["summary"]` runs the full gauntlet and
commits release metadata; `--publish` builds a clean DMG, signs with Developer ID,
notarizes, staples, byte-verifies, then atomically pushes `master` and the tag and
publishes the GitHub release. Notes live in `portable/docs/releases/`.

- **Do not increase the build number until the current one has been tagged and
  pushed.** Preparing stops before tagging, so a prepared-but-unpublished release
  can be re-prepared at the same version and build as many times as needed. Only a
  tag that actually reached the remote makes a number spent.
- `readme.md` must describe what the release ships. The prepare step fails when the
  README's content has not changed since the previous tag (the automated version
  badge does not count); a release that genuinely changes nothing user-visible says
  so with `SPDF_README_UNCHANGED=1`.
- A draft release is verified with `gh release view`, never the REST
  "release by tag name" endpoint, which never resolves drafts.

## Working alongside the user

The user often has the app open while work is in progress. **Do not launch, quit,
or screenshot ShenzhenPDF for verification.** Verify headlessly — unit suites and
probe binaries that write PNGs you can sample programmatically — and launch the app
only when explicitly asked.

## Legacy Windows tree (`src/`)

Only relevant when working on the inherited Win32 code. It uses Win32 APIs and its
own string/container helpers in `src/utils` rather than the STL; settings, commands
and flags are generated (`cmd/gen-settings.ts`, `cmd/gen-commands.ts`,
`cmd/gen-flags.ts`) and their outputs must be regenerated rather than hand-edited.
