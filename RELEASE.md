# Releasing Cuttings

How to cut a public Cuttings release. What users download is the **macOS app**,
so a release is a signed `.dmg` published on GitHub plus a Sparkle appcast entry
that points at it.

Everything here runs **on a Mac** with Xcode 16+ — the DMG build needs
`xcodebuild`, code signing, and notarization, none of which work in the Linux dev
sandbox. Commands run from the `macos/` sub-repo unless noted; paths like
`Sources/…` are relative to `macos/`.

Record what changed in [CHANGELOG.md](./CHANGELOG.md) as part of the release.

## 1. Bump the version

Edit `macos/Sources/Cuttings/App/Info.plist`:

- `CFBundleShortVersionString` — the marketing version (e.g. `0.1.1`).
- `CFBundleVersion` — a monotonically increasing build number (e.g. `2`). Sparkle
  compares this (`sparkle:version`) to decide whether an update is newer, so it
  **must** go up every release.

Add the matching entry to [CHANGELOG.md](./CHANGELOG.md).

## 2. Build, sign, notarize, staple, and Sparkle-sign the DMG

`make release` runs the whole chain and prints the appcast signature at the end.
It needs a Developer ID Application certificate and a `notarytool` credentials
profile (created once with `xcrun notarytool store-credentials`):

```bash
cd macos
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=cuttings-notary \
make release
```

Note the two values it prints — you'll paste them into the appcast:

- `sparkle:edSignature`
- `length` (the DMG size in bytes)

The signed DMG lands at `macos/dist/Cuttings.dmg`. Rename it to match the tag
before uploading — the appcast enclosure URL and the GitHub release asset must use
this exact name:

```bash
mv dist/Cuttings.dmg dist/Cuttings-0.1.1.dmg
```

> `make dmg` is the ad-hoc, local-testing path only — it is **not** notarized, so
> Gatekeeper and Sparkle will reject it for public distribution.

## 3. Publish the GitHub release

Tag and upload the DMG to the configured macOS repository. The appcast enclosure URL (next step)
points at exactly this asset, so the tag and file name must line up:

```bash
cd macos
git tag v0.1.1
git push origin v0.1.1
gh release create v0.1.1 dist/Cuttings-0.1.1.dmg \
  --title "Cuttings 0.1.1" \
  --notes "See the 0.1.1 section of CHANGELOG.md in the root project."
```

Copy the release asset URL printed by GitHub; the appcast must use that exact URL.

## 4. Publish the appcast

This repository deliberately has no website. Publish `appcast.xml` at the feed URL configured by
the app's `SUFeedURL`. Add a new `<item>` at the top of `<channel>`, using the `edSignature` and
`length` printed by `make release`:

```xml
<item>
  <title>0.1.1</title>
  <sparkle:version>2</sparkle:version>
  <sparkle:shortVersionString>0.1.1</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <enclosure
    url="PASTE_GITHUB_RELEASE_ASSET_URL_HERE"
    sparkle:edSignature="PASTE_ED_SIGNATURE_HERE"
    length="PASTE_LENGTH_HERE"
    type="application/octet-stream" />
</item>
```

`sparkle:version` must equal the `CFBundleVersion` from step 1.

## 5. Verify

- Download the DMG from the GitHub release on a clean Mac and confirm it opens
  without a Gatekeeper warning (proves signing + notarization + stapling).
- On a machine running the previous version, choose **Check for Updates…** and
  confirm Sparkle offers the new build (validates the appcast entry and signature).
- Fetch the configured appcast URL directly and confirm its enclosure resolves to the new DMG.
