# Release notes

User-facing notes for changes merged since the last release (26.7.17 build 1).
The in-app updater shows the section above the first `---` of a release body as
plain text with a 500-character cap.

## Cutting a release

Create and review committed metadata without publishing:

```sh
./portable/cut-release.sh --version YY.M.DD --build N --prepare-only \
  "commit summary"
```

The script reads tracked notes from `portable/docs/releases/YY.M.DD-N.md`. If
that file is missing, it seeds it and stops for editing. Once the prepared
commit is validated on `master`, run `./portable/cut-release.sh --publish` to
build, notarize, verify, tag, push, and publish. The publish operation is
idempotent for exact prior state and rejects collisions. `--dry-run` validates
and tests without changes.

## Next release

Nothing yet.
