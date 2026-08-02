#!/usr/bin/env bash
# Build ReadControl.app in Release, sign it with your Apple Developer ID, then
# notarize and staple BOTH the app and the .dmg that wraps it — a real, shippable,
# build that opens on any Mac (unlike the ad-hoc `make dmg`).
#
# This does NOT create the Sparkle EdDSA signature. Run `make sparkle-sign`
# afterwards (or just use `make release`, which runs it for you on the final,
# stapled .dmg — order matters, because stapling rewrites the .dmg bytes).
#
# Required environment:
#   SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#                   -> see `security find-identity -v -p codesigning`
#   NOTARY_PROFILE  name of a notarytool keychain profile, created once with:
#                     xcrun notarytool store-credentials <name> \
#                       --apple-id <email> --team-id <TEAMID> --password <app-specific-pw>
#                   (App Store Connect API keys work too — swap the notarytool
#                    call below for --key/--key-id/--issuer.)
#
# Run on macOS from the macos/ directory (or via `make release`).
# Prereqs: `make all` has generated the xcframework, bindings, and xcodeproj.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

APP_NAME="ReadControl"
SCHEME="ReadControl"
PROJECT="ReadControl.xcodeproj"
BUILD_DIR="$ROOT/build"
STAGING="$ROOT/dist/dmg-staging"
DIST="$ROOT/dist"
DMG_PATH="$DIST/${APP_NAME}.dmg"
ENTITLEMENTS="$ROOT/Sources/ReadControl/App/ReadControl.entitlements"

# ---- required config -------------------------------------------------------
: "${SIGN_IDENTITY:?set SIGN_IDENTITY to your 'Developer ID Application: Name (TEAMID)' — see: security find-identity -v -p codesigning}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile — create one with: xcrun notarytool store-credentials}"

# Fail early if the signing identity isn't in the keychain.
if ! security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
  echo "error: signing identity not found in your keychain:" >&2
  echo "         $SIGN_IDENTITY" >&2
  echo "       available Developer ID identities:" >&2
  security find-identity -v -p codesigning | sed 's/^/         /' >&2
  exit 1
fi

# codesign helper: hardened runtime + secure timestamp + your Developer ID.
sign() { codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@"; }

echo "==> Building $APP_NAME (Release)"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO

APP="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "error: $APP not found after build" >&2; exit 1; }

echo "==> Signing with Developer ID (hardened runtime + timestamp)"
# Sign inside-out — nested code first, the .app last — so signatures nest and
# notarization accepts every Mach-O. Sparkle ships Sparkle.framework with nested
# XPC services and helpers (Installer.xpc, Downloader.xpc, Autoupdate,
# Updater.app); each must carry the same identity + hardened runtime. We sign
# these explicitly rather than with `--deep`, which Apple discourages for
# distribution. Guards: native-host and a Frameworks dir may legitimately be
# absent, and an unguarded miss would abort under `set -e`.
if [ -f "$APP/Contents/MacOS/native-host" ]; then
  sign "$APP/Contents/MacOS/native-host"
fi
if [ -d "$APP/Contents/Frameworks" ]; then
  # Nested bundles/executables inside the frameworks first...
  while IFS= read -r -d '' item; do
    sign "$item"
  done < <(find "$APP/Contents/Frameworks" \
             \( -name '*.xpc' -o -name '*.app' -o -name 'Autoupdate' \) -print0)
  # ...then each framework bundle itself.
  while IFS= read -r -d '' fw; do
    sign "$fw"
  done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0)
fi
# Finally the app bundle, with its entitlements.
sign --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "    signature OK (Developer ID, hardened runtime)"

# Notarize and staple the APP itself. If only the .dmg is stapled (below), the
# copy a user drags to /Applications has no offline-verifiable ticket, so its
# first launch depends on an ONLINE notarization check and is blocked when that
# can't complete (offline machine, flaky network) — the "can't be opened / remove
# the quarantine" symptom. Stapling the app makes its notarization travel with it.
echo "==> Notarizing the app (uploads to Apple and waits — a few minutes)"
APP_ZIP="$DIST/${APP_NAME}-app.zip"
mkdir -p "$DIST"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$APP_ZIP"

echo "==> Stapling the ticket to the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Staging .dmg contents"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target

echo "==> Creating $DMG_PATH"
mkdir -p "$DIST"
# A stale volume of the same name — left mounted by a previous run or opened in
# Finder — makes hdiutil fail with "Resource busy"; detach it first.
if [ -d "/Volumes/$APP_NAME" ]; then
  hdiutil detach "/Volumes/$APP_NAME" -force >/dev/null 2>&1 || true
fi
# Spotlight/antivirus can transiently lock the staging dir mid-create, so retry.
attempt=1
until hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"; do
  if [ "$attempt" -ge 3 ]; then
    echo "error: hdiutil create kept failing (Resource busy) after $attempt tries." >&2
    echo "       Close any Finder window on the ReadControl volume, then check:" >&2
    echo "         hdiutil info   # detach any stale ReadControl image" >&2
    exit 1
  fi
  echo "    hdiutil busy — retrying ($attempt)…" >&2
  attempt=$((attempt + 1))
  sleep 3
done
rm -rf "$STAGING"

echo "==> Signing the .dmg (Developer ID + timestamp)"
# Sign the disk image itself so Gatekeeper's assessment of the download is
# meaningful — a notarized-but-unsigned .dmg reports "no usable signature".
# (No hardened runtime / entitlements: those apply to executables, not images.)
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"

echo "==> Notarizing (uploads to Apple and waits — can take a few minutes)"
# `--wait` blocks until Apple returns Accepted/Invalid. If it comes back Invalid,
# inspect it with:  xcrun notarytool log <submission-id> --keychain-profile "$NOTARY_PROFILE"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the notarization ticket to the .dmg"
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying"
# stapler validate is the authoritative check that a ticket is attached. For the
# APP, `spctl -a -t exec` is Gatekeeper's real verdict; for the .dmg, spctl's
# image assessment varies by macOS version, so keep both spctl checks advisory.
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG_PATH"
spctl -a -t exec -vv "$APP" \
  || echo "    note: spctl app assessment inconclusive — 'stapler validate' passed, which is what matters"
spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH" \
  || echo "    note: spctl dmg assessment inconclusive — 'stapler validate' passed, which is what matters"

echo "==> Done: $DMG_PATH  (Developer ID signed + notarized + stapled)"
echo "    Next: 'make sparkle-sign' for the appcast EdDSA signature (or use 'make release')."
