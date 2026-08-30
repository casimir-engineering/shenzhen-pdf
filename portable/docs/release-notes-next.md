# Release notes

User-facing notes for changes merged since the last release (26.8.30 build 1).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- **Shenzhen Files is now the app's file manager when it is installed.** No setting to find: if Shenzhen Files is on the Mac, Open… (Cmd+O), the Cmd+Shift+O path prompt, and Show in Folder all go there, opened at the folder you are most likely to want — the current document's, else the last one you opened, else your home folder. *Settings ▸ File Manager* still switches back to Finder, an explicit choice always wins over the automatic one, and anything that cannot reach Shenzhen Files falls back to Finder. Save panels stay native, because a save has to hand a destination back to the app.
