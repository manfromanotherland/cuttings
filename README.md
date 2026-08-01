# macos

The macOS client (Swift / SwiftUI) for **ReadControl**, a local-first read-it-later system.
Browse, read, search, and tag your saved readings, organized by smart views
(All / Unread / Archive / Favorites). It embeds the Rust engine (`core`) via UniFFI
and watches the library folder for changes that arrive via the user's own sync.

**License:** GPL-3.0-or-later — see [LICENSE](./LICENSE). This is the copyleft application of the
project; the engine and plugin are MIT. Redistributing a modified build requires sharing your
source under the GPL.

Part of the **ReadControl** project →
[github.com/readcontrol/root](https://github.com/readcontrol/root)
(architecture, UI design, library-format contract, and backlog). The Rust engine lives in
[core](https://github.com/readcontrol/core).

## Prerequisites

- macOS 14 or later
- Xcode 15 or later
- [Homebrew](https://brew.sh)
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) and
  [SwiftLint](https://github.com/realm/SwiftLint) for formatting and linting. Both are pinned in
  `.mise.toml`, so `mise install` fetches the same versions this repo expects; alternatively
  `brew install swiftformat swiftlint`.
- Rust targets for cross-compilation (needed to build the XCFramework):

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

The [core](https://github.com/readcontrol/core) repo must be cloned as
a sibling of this repo (i.e. `../core`) — the `Makefile` references it there.

## Setup

Run this once after cloning (and again after updating `core`):

```bash
make all
```

This will:
1. Build the `core` Rust library as a universal XCFramework (`make xcframework`)
2. Copy the generated Swift bindings into `GeneratedBindings/` (`make bindings`)
3. Generate `ReadControl.xcodeproj` from `project.yml` (`make xcodegen`)

## Run

Open the generated project in Xcode and press **Run**:

```bash
open ReadControl.xcodeproj
```

Or build from the command line:

```bash
xcodebuild build -project ReadControl.xcodeproj -scheme ReadControl
```

## Running the tests

There are two suites, and the scheme runs them in this order:

- **`ReadControlTests`** — fast, hostless unit tests for pure app logic (smart-view membership,
  reading-time formatting). They compile the files under test directly instead of hosting in the
  app, so they never launch a window or touch your real library or defaults.
- **`ReadControlUITests`** — the end-to-end XCUITest suite. It launches the real app against a
  throwaway temp library and drives it through the UI.

Both are dependency-free: only Xcode and the macOS SDK, no third-party test libraries.

Run everything (unit tests first, then UI):

```bash
make test        # xcodebuild test -scheme ReadControl
```

Regenerate the project after adding or removing test files:

```bash
make xcodegen
```

Compile the test bundles without running — the fastest way to surface Swift compile errors:

```bash
xcodebuild build-for-testing -scheme ReadControl
```

Run just the fast unit suite, or a single test class or test, while iterating:

```bash
xcodebuild test -scheme ReadControl -only-testing:ReadControlTests
xcodebuild test -scheme ReadControl -only-testing:ReadControlUITests/SmokeTest
xcodebuild test -scheme ReadControl -only-testing:ReadControlUITests/SmokeTest/testLaunchCountsOpenAndSearch
```

Run the whole suite, capturing results (screenshots-on-failure and logs land in the bundle):

```bash
xcodebuild test -scheme ReadControl -resultBundlePath Results.xcresult
```

Pipe any of these through `xcbeautify` (`brew install xcbeautify`) for readable logs, and open
`Results.xcresult` in Xcode — or extract attachments with `xcparse` — to inspect failures.

### First run: permissions & signing

- **Accessibility + Automation.** XCUITest synthesizes keyboard/mouse events and controls the app,
  so the process running the tests needs permission. Grant the terminal app (or Xcode) both
  **Accessibility** and **Automation** under System Settings → Privacy & Security; the first run
  also prompts to allow controlling `ReadControl` — accept it.
- **Signing.** If CLI signing fails for the new `ReadControlUITests` bundle, set a development team
  (`DEVELOPMENT_TEAM`) or enable automatic signing in Xcode once.
- **Hardened runtime.** If the app fails to launch under test, set `ENABLE_HARDENED_RUNTIME: NO`
  for the **Debug** config only (in `project.yml`, then `make xcodegen`).
- **Keyboard focus.** A running test steals keyboard focus and the suite runs serially
  (`parallelizable: false`) — don't type on the machine while it runs.

### Known host quirk: dropped keystrokes

On some Macs, XCUITest's `typeText` drops the letter **"c"** and the **first keystroke** into a
freshly focused field (`"coffee"` → `"offee"`), while paste (`⌘V`) inserts text correctly. If
search/tag tests fail with mangled input, disable press-and-hold and restart, or check the active
keyboard layout:

```bash
defaults write -g ApplePressAndHoldEnabled -bool false
```

The suite already routes search text through the pasteboard (`ReadingListPage.pasteSearch`) to
sidestep this, so it isn't machine-dependent.

## Software updates (Sparkle)

The app ships in-app updates via [Sparkle](https://sparkle-project.org). It's added as a Swift
Package (`project.yml` → `packages.Sparkle`), so Xcode embeds and signs `Sparkle.framework`
automatically — no manual embed phase. A **Check for Updates…** item sits in the app menu just
below *About ReadControl*; the updater is created in `ReadControlApp.init` and left dormant under
UI testing so the XCUITest suite stays offline. It's scoped to the update path only — it doesn't
touch the core, the library format, or domain behavior.

Sparkle reads two keys from `Sources/ReadControl/App/Info.plist`:

- `SUFeedURL` — the public URL of your `appcast.xml` feed.
- `SUPublicEDKey` — your Sparkle EdDSA (Ed25519) **public** key.

Both currently hold placeholders, so a locally-built app checks nothing (Sparkle refuses to install
an update it can't verify). To actually ship updates:

1. **Generate a signing key once** (stored in your login Keychain — never commit the private key):

   ```bash
   ./bin/generate_keys        # from the Sparkle distribution / SwiftPM artifact
   ```

   Copy the printed public key into `SUPublicEDKey` and re-run `make xcodegen` if you changed the
   plist path.

2. **Host the appcast.** Point `SUFeedURL` at where you'll publish `appcast.xml`, and bump
   `CFBundleShortVersionString` / `CFBundleVersion` in `Info.plist` for each release — Sparkle
   compares them to decide when an update is available.

3. **Sign & publish each build.** After building the `.dmg`, sign it and add the entry to the
   appcast:

   ```bash
   make sparkle-sign      # signs dist/ReadControl.dmg; prints the appcast enclosure attributes
   ```

   This wraps Sparkle's `sign_update` (auto-found in the SPM artifact) using the private key in
   your Keychain, and prints the `sparkle:edSignature` and `length` to paste into the
   `<enclosure>` element of `appcast.xml`.

Note: the ad-hoc-signed `.dmg` from `make dmg` is fine for local testing, but a public
auto-updating build must be **Developer ID signed and notarized** — Sparkle's installer (and
Gatekeeper) reject an ad-hoc signature on the downloaded update. See `scripts/package-dmg.sh`.

## Formatting & linting

Two tools keep the Swift sources consistent, and they're set up to cooperate rather than fight:

- **SwiftFormat** (`.swiftformat`) rewrites code — indentation, spacing, redundant syntax.
- **SwiftLint** (`.swiftlint.yml`) checks code — style and the size/complexity thresholds.

SwiftFormat is configured to agree with SwiftLint's rules (most notably `--commas inline`, so it
never adds the trailing commas that SwiftLint's `trailing_comma` rule flags), so running the
formatter won't introduce lint violations. Run them in this order:

```bash
make format        # swiftformat . — rewrites sources in place
make lint          # swiftlint lint — reports remaining violations
```

Other targets:

```bash
make format-check  # swiftformat --lint . — fail if anything is unformatted (CI / pre-commit)
make lint-fix      # swiftlint --fix — auto-correct the safe SwiftLint violations
```

Both configs exclude the generated bindings, the vendored framework, and build output.

## Debugging: SQL tracing

The app embeds `core`, which logs every SQL statement to stderr when the `SQL_TRACE`
environment variable is set — handy for checking whether the UI is issuing too many queries. See
the [core README](../core/README.md#debugging-sql-tracing) for the output format and a
one-liner that ranks statements by frequency.

First rebuild the framework so the app links the traced core:

```bash
make xcframework
```

Then launch the app with the variable set:

- **From Xcode** — Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables, add
  `SQL_TRACE = 1`, then Run. The `[sql …]` lines print to the debug console.
- **From the terminal** — run the built binary directly so stderr streams to your terminal
  (launching from Finder or `open` hides it):

```bash
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/ReadControl-*/Build/Products/Debug/ReadControl.app | head -1)
SQL_TRACE=1 "$APP/Contents/MacOS/ReadControl"
```

The logs go to stderr only — not a file or Console.app. To keep them, redirect:
`SQL_TRACE=1 "$APP/Contents/MacOS/ReadControl" 2>&1 | tee ~/readcontrol-sql.log`.

## Other make targets

```bash
make xcframework   # rebuild the XCFramework from core
make bindings      # copy generated Swift bindings (runs xcframework first)
make xcodegen      # regenerate ReadControl.xcodeproj from project.yml
make sparkle-sign  # sign the built .dmg with your Sparkle key (see Software updates)
make format        # reformat Swift sources with SwiftFormat
make format-check  # check formatting without editing
make lint          # lint Swift sources with SwiftLint
make lint-fix      # auto-fix safe SwiftLint violations
make clean         # remove Frameworks/, GeneratedBindings/, and ReadControl.xcodeproj
```
