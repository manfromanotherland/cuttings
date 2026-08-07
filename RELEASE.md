# Releasing ReadControl

How to cut a public ReadControl release. What users download is the **macOS app**,
so a release is a signed `.dmg` published on GitHub plus a Sparkle appcast entry
that points at it.

Everything here runs **on a Mac** with Xcode 16+ — the DMG build needs
`xcodebuild`, code signing, and notarization, none of which work in the Linux dev
sandbox. Commands run from the `macos/` sub-repo unless noted; paths like
`Sources/…` are relative to `macos/`.

Record what changed in [CHANGELOG.md](./CHANGELOG.md) as part of the release.

## 1. Bump the version

Edit `macos/Sources/ReadControl/App/Info.plist`:

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
NOTARY_PROFILE=readcontrol-notary \
make release
```

Note the two values it prints — you'll paste them into the appcast:

- `sparkle:edSignature`
- `length` (the DMG size in bytes)

The signed DMG lands at `macos/dist/ReadControl.dmg`. Rename it to match the tag,
e.g. `ReadControl-0.1.1.dmg`, before uploading.

> `make dmg` is the ad-hoc, local-testing path only — it is **not** notarized, so
> Gatekeeper and Sparkle will reject it for public distribution.

## 3. Publish the GitHub release

Tag and upload the DMG to the `readcontrol/macos` repo. The appcast enclosure URL
(next step) points at exactly this asset, so the tag and file name must line up:

```bash
cd macos
git tag v0.1.1
git push origin v0.1.1
gh release create v0.1.1 dist/ReadControl-0.1.1.dmg \
  --title "0.1.1" \
  --notes "See the 0.1.1 section of CHANGELOG.md."
```

This produces the URL the appcast expects:
`https://github.com/readcontrol/macos/releases/download/v0.1.1/ReadControl-0.1.1.dmg`

## 4. Update the website (appcast + download link)

Both the Sparkle appcast and the homepage **Download for macOS** button live in the
[`readcontrol/website`](https://github.com/readcontrol/website) repo. Update both,
then deploy — they must point at the DMG published in step 3.

### 4a. Appcast

Sparkle-based auto-updates come from `public/appcast.xml`, served at
<https://www.readcontrol.app/appcast.xml> (the `SUFeedURL` baked into the app). Add
a new `<item>` at the top of `<channel>`, using the `edSignature` and `length`
printed by `make release`:

```xml
<item>
  <title>0.1.1</title>
  <sparkle:version>2</sparkle:version>
  <sparkle:shortVersionString>0.1.1</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <enclosure
    url="https://github.com/readcontrol/macos/releases/download/v0.1.1/ReadControl-0.1.1.dmg"
    sparkle:edSignature="PASTE_ED_SIGNATURE_HERE"
    length="PASTE_LENGTH_HERE"
    type="application/octet-stream" />
</item>
```

`sparkle:version` must equal the `CFBundleVersion` from step 1.

### 4b. Download CTA

The homepage **Download for macOS** button points at a hard-coded DMG URL. Bump the
`DOWNLOAD` constant in `app/page.tsx` to the new release so new visitors get the
latest build (existing installs update via the appcast above):

```ts
const DOWNLOAD =
  "https://github.com/readcontrol/macos/releases/download/v0.1.1/ReadControl-0.1.1.dmg";
```

Commit, push, and deploy the website so the feed and the download link are both live.

## 5. Verify

- Download the DMG from the GitHub release on a clean Mac and confirm it opens
  without a Gatekeeper warning (proves signing + notarization + stapling).
- On a machine running the previous version, choose **Check for Updates…** and
  confirm Sparkle offers the new build (validates the appcast entry and signature).
- On <https://www.readcontrol.app>, click **Download for macOS** and confirm it
  pulls the new DMG (validates the `DOWNLOAD` link).
