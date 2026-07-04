# Packaging (U9)

One codebase, two build variants (R13/R14). No Xcode required — SPM + the
assembly script produce signed `.app` bundles.

## Build variants

| Variant | Command | Sandbox | Signing for release |
|---|---|---|---|
| Direct (default) | `./Packaging/scripts/make-app.sh app-direct` | No (KTD4 fallback access model) | `SIGN_IDENTITY="Developer ID Application: …" HARDENED=1` |
| Mac App Store | `./Packaging/scripts/make-app.sh app-mas` | Yes — mandatory | `SIGN_IDENTITY="3rd Party Mac Developer Application: …"` |
| U1 spike | `…/make-app.sh spike` / `spike-usb` | Yes | ad-hoc (local diagnostic only) |

The MAS variant ships **only if the U1 spike is GO** (`Spike/README.md`).

## Direct release checklist (Developer ID)

1. `SIGN_IDENTITY="Developer ID Application: <team>" HARDENED=1 ./Packaging/scripts/make-app.sh app-direct`
2. Wrap in a DMG: `hdiutil create -volname "Blu-Ray Burner" -srcfolder "dist/Blu-Ray Burner.app" -ov -format UDZO dist/BluRayBurner.dmg`
3. Notarize: `xcrun notarytool submit dist/BluRayBurner.dmg --keychain-profile <profile> --wait`
4. Staple: `xcrun stapler staple dist/BluRayBurner.dmg`
5. Smoke: mount the DMG on a clean machine, launch, burn per runbook row 1.

Requires an Apple Developer account with a Developer ID certificate in the
keychain and a notarytool keychain profile (`xcrun notarytool store-credentials`).

## MAS release checklist (only after U1 GO)

1. Build `app-mas` signed with the 3rd-party Mac developer certs.
2. Package: `productbuild --component "dist/Blu-Ray Burner.app" /Applications --sign "3rd Party Mac Developer Installer: <team>" dist/BluRayBurner.pkg`
3. Upload via Transporter / `xcrun altool`; App Store Connect handles pricing (R15) and updates.

## Version bumping

`CFBundleShortVersionString` / `CFBundleVersion` live in `Packaging/Info-App.plist`.
