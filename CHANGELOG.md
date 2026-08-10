# Changelog

All notable changes to ReadControl (the macOS app users download) are recorded
here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions track the app's `CFBundleShortVersionString`. See
[RELEASE.md](./RELEASE.md) for how a release is cut.

## 0.2.0 - 2026-08-10

### Added

- Onboarding and Settings › Extensions link to the browser extension on the
  Chrome Web Store and Firefox Add-ons, now that the listings are public.

### Changed

- Onboarding is now a compact two-step sheet (choose a library, then add the
  extension); the main window opens larger on first run and keeps the size you
  leave it at afterward.
- Refreshed the welcome article copy.

### Removed

- The bundled extension download and its load-unpacked (sideload) instructions,
  replaced by the store links above.

## 0.1.1 - 2026-08-07

### Added

- Onboarding step after choosing a library: download the browser extension and
  load it unpacked, with a link to the source at
  <https://github.com/readcontrol/extension>.
- Settings › Extensions offers the same extension download and load-unpacked
  instructions for Chrome/Edge/Brave and Firefox.

### Changed

- Settings › Extensions no longer links to the Chrome Web Store / Firefox Add-ons
  listings while the extension is still under review; it hands out the packaged
  download instead.

## 0.1.0

- Initial release: browse, read, search, tag, and rate your library; native
  SwiftUI reader; in-app updates via Sparkle.
