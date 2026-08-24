#!/usr/bin/env bash
# Build Cuttings.app in Release and wrap it in a distributable .dmg.
#
# No Apple Developer ID is required: the app is signed ad-hoc (`codesign -s -`),
# which is enough to run locally but is NOT notarized. On another Mac, Gatekeeper
# will quarantine it — the recipient must right-click the app → Open once, or run
#   xattr -dr com.apple.quarantine /Applications/Cuttings.app
#
# Run this on macOS from the macos/ directory (or via `make dmg`).
# Prereqs: `make all` has generated the xcframework, bindings, and xcodeproj.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

APP_NAME="Cuttings"
SCHEME="Cuttings"
PROJECT="Cuttings.xcodeproj"
BUILD_DIR="$ROOT/build"
STAGING="$ROOT/dist/dmg-staging"
DIST="$ROOT/dist"
DMG_PATH="$DIST/${APP_NAME}.dmg"

echo "==> Building $APP_NAME (Release)"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO

APP="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "error: $APP not found after build" >&2; exit 1; }

echo "==> Ad-hoc signing (no Developer ID)"
# Sign inner Mach-O first, then the app bundle, so signatures nest correctly.
# `--deep` on the app also covers nested code, but signing these explicitly
# avoids ordering issues on some toolchains. Each step is guarded: the
# cuttings-native-host binary and a Frameworks dir may legitimately be absent (e.g. a
# statically linked core), and an unguarded failure would abort under pipefail.
#
# Sparkle ships as Sparkle.framework in Contents/Frameworks (with nested XPC
# services and helper apps); the framework loop below signs the bundle and the
# final `--deep` pass re-signs its nested code. This is enough to *run* an
# ad-hoc build locally. A public, auto-updating build needs a real Developer ID
# signature + notarization instead — see README "Software updates (Sparkle)".
if [ -f "$APP/Contents/MacOS/cuttings-native-host" ]; then
  codesign --force --timestamp=none -s - "$APP/Contents/MacOS/cuttings-native-host"
fi
if [ -d "$APP/Contents/Frameworks" ]; then
  while IFS= read -r -d '' fw; do
    codesign --force --timestamp=none -s - "$fw"
  done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0)
fi
codesign --force --deep --timestamp=none -s - "$APP"
codesign --verify --deep --strict "$APP"
echo "    signature OK (ad-hoc)"

echo "==> Staging .dmg contents"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target

echo "==> Creating $DMG_PATH"
mkdir -p "$DIST"
# Detach a stale same-name volume (a previous run or Finder mount) — otherwise
# hdiutil fails with "Resource busy" — then retry through transient Spotlight/AV
# locks on the staging dir.
if [ -d "/Volumes/$APP_NAME" ]; then
  hdiutil detach "/Volumes/$APP_NAME" -force >/dev/null 2>&1 || true
fi
attempt=1
until hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"; do
  if [ "$attempt" -ge 3 ]; then
    echo "error: hdiutil create kept failing (Resource busy) after $attempt tries." >&2
    echo "       Close any Finder window on the Cuttings volume; see 'hdiutil info'." >&2
    exit 1
  fi
  echo "    hdiutil busy — retrying ($attempt)…" >&2
  attempt=$((attempt + 1))
  sleep 3
done

rm -rf "$STAGING"
echo "==> Done: $DMG_PATH"
echo "    NOTE: unsigned/un-notarized — recipient must bypass Gatekeeper once."
