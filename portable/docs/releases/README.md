# Release notes archive

Each published release has one tracked `YY.M.DD-BUILD.md` file in this
directory. Keep concise markdown bullets above exactly one standalone `---`
divider and detailed notes below it. The updater displays the first section
through the same formatter used by `make -C portable release-notes-preview`.

Do not move release notes into `dist/`: that directory is ignored build output
and cannot reproduce a published release from a clean checkout.
