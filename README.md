# read-later-macos

The macOS client (Swift / SwiftUI) for **read-later**, a local-first read-it-later system.
Browse, read, search, and tag your saved readings, organized by smart views
(All / Unread / Archive / Favorites). It embeds the Rust engine (`read-later-core`) via UniFFI
and watches the library folder for changes that arrive via the user's own sync.

**License:** GPL-3.0-or-later — see [LICENSE](./LICENSE). This is the copyleft application of the
project; the engine and plugin are MIT. Redistributing a modified build requires sharing your
source under the GPL.

Part of the **read-later** project →
[github.com/boniattirodrigo/read-later-main](https://github.com/boniattirodrigo/read-later-main)
(architecture, UI design, library-format contract, and backlog). The Rust engine lives in
[read-later-core](https://github.com/boniattirodrigo/read-later-core).

## Prerequisites

- macOS 14 or later
- Xcode 15 or later
- [Homebrew](https://brew.sh)
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Rust targets for cross-compilation (needed to build the XCFramework):

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

The [read-later-core](https://github.com/boniattirodrigo/read-later-core) repo must be cloned as
a sibling of this repo (i.e. `../read-later-core`) — the `Makefile` references it there.

## Setup

Run this once after cloning (and again after updating `read-later-core`):

```bash
make all
```

This will:
1. Build the `read-later-core` Rust library as a universal XCFramework (`make xcframework`)
2. Copy the generated Swift bindings into `GeneratedBindings/` (`make bindings`)
3. Generate `ReadLater.xcodeproj` from `project.yml` (`make xcodegen`)

## Run

Open the generated project in Xcode and press **Run**:

```bash
open ReadLater.xcodeproj
```

Or build from the command line:

```bash
xcodebuild build -project ReadLater.xcodeproj -scheme ReadLater
```

## Debugging: SQL tracing

The app embeds `read-later-core`, which logs every SQL statement to stderr when the `SQL_TRACE`
environment variable is set — handy for checking whether the UI is issuing too many queries. See
the [core README](../read-later-core/README.md#debugging-sql-tracing) for the output format and a
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
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/ReadLater-*/Build/Products/Debug/ReadLater.app | head -1)
SQL_TRACE=1 "$APP/Contents/MacOS/ReadLater"
```

The logs go to stderr only — not a file or Console.app. To keep them, redirect:
`SQL_TRACE=1 "$APP/Contents/MacOS/ReadLater" 2>&1 | tee ~/read-later-sql.log`.

## Other make targets

```bash
make xcframework   # rebuild the XCFramework from read-later-core
make bindings      # copy generated Swift bindings (runs xcframework first)
make xcodegen      # regenerate ReadLater.xcodeproj from project.yml
make clean         # remove Frameworks/, GeneratedBindings/, and ReadLater.xcodeproj
```
