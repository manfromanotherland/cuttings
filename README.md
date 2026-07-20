# readcontrol-macos

The macOS client (Swift / SwiftUI) for **Read Control**, a local-first read-it-later system.
Browse, read, search, and tag your saved readings, organized by smart views
(All / Unread / Archive / Favorites). It embeds the Rust engine (`readcontrol-core`) via UniFFI
and watches the library folder for changes that arrive via the user's own sync.

**License:** GPL-3.0-or-later — see [LICENSE](./LICENSE). This is the copyleft application of the
project; the engine and plugin are MIT. Redistributing a modified build requires sharing your
source under the GPL.

Part of the **Read Control** project →
[github.com/boniattirodrigo/readcontrol-main](https://github.com/boniattirodrigo/readcontrol-main)
(architecture, UI design, library-format contract, and backlog). The Rust engine lives in
[readcontrol-core](https://github.com/boniattirodrigo/readcontrol-core).

## Prerequisites

- macOS 14 or later
- Xcode 15 or later
- [Homebrew](https://brew.sh)
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Rust targets for cross-compilation (needed to build the XCFramework):

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

The [readcontrol-core](https://github.com/boniattirodrigo/readcontrol-core) repo must be cloned as
a sibling of this repo (i.e. `../readcontrol-core`) — the `Makefile` references it there.

## Setup

Run this once after cloning (and again after updating `readcontrol-core`):

```bash
make all
```

This will:
1. Build the `readcontrol-core` Rust library as a universal XCFramework (`make xcframework`)
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

The end-to-end suite is XCUITest (`ReadControlUITests`) — it launches the real app against a
throwaway temp library and drives it through the UI. It's dependency-free: only Xcode and the
macOS SDK, no third-party test libraries.

Regenerate the project after adding or removing test files:

```bash
make xcodegen
```

Compile the test bundle without running — the fastest way to surface Swift compile errors:

```bash
xcodebuild build-for-testing -scheme ReadControl
```

Run a single test class (or a single test) while iterating:

```bash
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

## Debugging: SQL tracing

The app embeds `readcontrol-core`, which logs every SQL statement to stderr when the `SQL_TRACE`
environment variable is set — handy for checking whether the UI is issuing too many queries. See
the [core README](../readcontrol-core/README.md#debugging-sql-tracing) for the output format and a
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
make xcframework   # rebuild the XCFramework from readcontrol-core
make bindings      # copy generated Swift bindings (runs xcframework first)
make xcodegen      # regenerate ReadControl.xcodeproj from project.yml
make clean         # remove Frameworks/, GeneratedBindings/, and ReadControl.xcodeproj
```
