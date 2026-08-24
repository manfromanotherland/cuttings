<p align="center">
  <img src="https://raw.githubusercontent.com/cuttings/root/main/assets/icon.png" alt="Cuttings" width="128">
</p>
<h1 align="center">Cuttings</h1>
<p align="center">
  The native macOS reading manager
  <br />
  <a href="https://github.com/cuttings/macos">macOS</a>
  ·
  <a href="https://github.com/cuttings/core">core</a>
  ·
  <a href="https://github.com/cuttings/extension">extension</a>
  ·
  <a href="https://github.com/cuttings/root">root</a>
</p>

---

# macos

The macOS client (Swift / SwiftUI) for **Cuttings**, the native macOS reading manager.
Browse, read, search, and tag your saved readings. It embeds the Rust engine (`core`) via UniFFI and watches
the library folder for changes that arrive via the user's own sync.

## Prerequisites

- macOS 14+ and Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) + [SwiftLint](https://github.com/realm/SwiftLint)
  (`brew install swiftformat swiftlint`, or `mise install` to match the pinned versions)
- Rust targets for the XCFramework build: `rustup target add aarch64-apple-darwin x86_64-apple-darwin`

The [core](https://github.com/cuttings/core) repo must sit as a sibling (`../core`) — the
`Makefile` references it there.

## Setup

Run once after cloning (and again after updating `core`):

```bash
make all        # build the core XCFramework, copy bindings, generate Cuttings.xcodeproj
```

## Run

```bash
open Cuttings.xcodeproj                                    # then press Run in Xcode
xcodebuild build -project Cuttings.xcodeproj -scheme Cuttings   # or from the CLI
```

## Test

```bash
make test       # runs the unit suite (CuttingsTests) then the UI suite (CuttingsUITests)
```

- `CuttingsTests` — fast, hostless unit tests for pure app logic.
- `CuttingsUITests` — end-to-end XCUITest against a throwaway temp library.

Both are dependency-free (Xcode + the macOS SDK only). Run one suite or test while iterating:

```bash
xcodebuild test -scheme Cuttings -only-testing:CuttingsTests
```

## Format & lint

SwiftFormat rewrites code; SwiftLint checks it. SwiftFormat is configured to agree with
SwiftLint, so formatting won't introduce lint violations. Run in this order:

```bash
make format     # swiftformat . — rewrites sources in place
make lint       # swiftlint lint — reports remaining violations
```

## Software updates (Sparkle)

The app ships in-app updates via [Sparkle](https://sparkle-project.org), added as a Swift Package.
A **Check for Updates…** item sits in the app menu below *About Cuttings*. Sparkle reads two
keys from `Sources/Cuttings/App/Info.plist`:

- `SUFeedURL` — the appcast feed, set to `https://www.cuttings.app/appcast.xml`.
- `SUPublicEDKey` — your Sparkle EdDSA public key (currently a placeholder; set it before your
  first public release, as it's baked into every shipped build).

### Shipping a release

A public build must be **Developer ID signed, notarized, and stapled** — Gatekeeper and Sparkle
both reject an ad-hoc signature on a downloaded update. `make release` does the whole chain
(sign → notarize → staple → Sparkle-sign) and prints the appcast `edSignature` + `length`:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=cuttings-notary \
make release
```

It needs a Developer ID Application certificate and a notarytool profile (created once with
`xcrun notarytool store-credentials`). Then upload the `.dmg` to GitHub Releases and add an
`<item>` to `appcast.xml` in the `website` repo.

`make dmg` is the ad-hoc, local-testing path only (not notarized).

## Make targets

```bash
make all           # build XCFramework + bindings + generate the Xcode project
make test          # run the test suites
make dmg           # ad-hoc-signed .dmg for local testing (not notarized)
make release       # Developer ID signed + notarized + stapled + Sparkle-signed .dmg
make format        # reformat with SwiftFormat
make lint          # lint with SwiftLint
make clean         # remove generated framework, bindings, and project
```

## Debugging

The embedded `core` logs every SQL statement to stderr when `SQL_TRACE=1` is set — see the
[core README](../core/README.md#debugging-sql-tracing).
