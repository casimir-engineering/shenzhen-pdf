# macOS TestFlight Handoff

This path is for a friend or maintainer who has an Apple Developer Program
membership and can publish the macOS beta through App Store Connect.

## What the publisher creates once

In Apple Developer and App Store Connect:

1. Create an explicit macOS Bundle ID, for example
   `com.example.sumatrapdf`.
2. Create an App Store Connect macOS app record using that Bundle ID.
3. Create a Mac App Store distribution provisioning profile for the Bundle ID.
4. Install an Apple Distribution certificate in Keychain.
5. Install a 3rd Party Mac Developer Installer certificate in Keychain.

The Bundle ID in App Store Connect must match `MAC_BUNDLE_ID` exactly.

## Build the upload package

From the repository root:

```sh
MAC_BUNDLE_ID=com.example.sumatrapdf \
MAC_VERSION=0.5.0 \
MAC_BUILD=6 \
MAC_APPSTORE_IDENTITY="Apple Distribution: Friend Name (TEAMID1234)" \
MAC_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Friend Name (TEAMID1234)" \
MAC_PROVISIONING_PROFILE="$HOME/Downloads/SumatraPDF_AppStore.provisionprofile" \
./portable/build-mac-testflight.sh
```

The script creates:

```text
dist/SumatraPDF-testflight-0.5.0-6.pkg
```

To open the package in Apple's Transporter app automatically:

```sh
OPEN_TRANSPORTER=1 ./portable/build-mac-testflight.sh ...
```

Transporter validates the package and delivers it to App Store Connect. After
processing, the publisher can add the build to TestFlight.

## Notes

- The normal local `.app` and DMG targets stay ad-hoc or Developer ID signed.
  TestFlight uses the separate `testflight-pkg` target.
- `MAC_VERSION` maps to `CFBundleShortVersionString`.
- `MAC_BUILD` maps to `CFBundleVersion` and must increase for every App Store
  Connect upload.
- The TestFlight target signs with `portable/mac/TestFlight.entitlements`, which
  enables App Sandbox, user-selected file read/write access, printing, and
  outbound network access. The sandbox is intentionally not used for local dev
  builds.
- If App Store review later objects to OCR installer behavior, keep OCR enabled
  for direct/notarized builds and gate it in the App Store/TestFlight build.
