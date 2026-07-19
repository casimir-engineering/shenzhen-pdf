# Linux packaging & release signing

## Artifacts

A Linux release publishes two assets next to the Mac DMG on the GitHub
release:

- `ShenzhenPDF-linux-amd64.deb` — built by `build-deb.sh` (the file it emits,
  `shenzhenpdf_<ver>_amd64.deb`, is renamed to this stable asset name at
  upload).
- `ShenzhenPDF-linux-amd64.deb.minisig` — minisign signature.

The in-app updater downloads both, verifies the signature against the pinned
public key (`minisign.pub`, also installed at
`/usr/share/shenzhenpdf/minisign.pub`), and installs via pkexec. Binary
installs under `$HOME` (tarball/user-local) self-update by atomic swap
instead.

## Building

    docker build -t shenzhen-build portable/linux/dev
    docker run --rm -v "$PWD:/work" -w /work shenzhen-build \
        bash -c 'make -C portable linux-gtk4 && portable/linux/pkg/build-deb.sh <version>'

## Signing (release machine only)

The secret key lives OUTSIDE the repo at
`~/.config/shenzhenpdf-release/minisign.key` (created 2026-07-19; currently
NOT password-protected — re-encrypt with `minisign -R` if it leaves this
machine).

    minisign -Sm dist/ShenzhenPDF-linux-amd64.deb \
        -s ~/.config/shenzhenpdf-release/minisign.key \
        -t "ShenzhenPDF <version>"

Public key (pinned in `spdf_updater.c` and shipped in the deb):

    RWTd0JXnmCT3lfku0las2n0Y63vQ1JN6xxfV7WRYdbOMoNX4on2o5azz
